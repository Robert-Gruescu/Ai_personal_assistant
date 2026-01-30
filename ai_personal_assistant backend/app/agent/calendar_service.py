"""
Google Calendar Service
Handles Google Calendar integration with Google Meet creation
"""
import os
import json
import pickle
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from pathlib import Path

# Google API imports
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from app.config import (
    GOOGLE_CALENDAR_CREDENTIALS_FILE,
    GOOGLE_CALENDAR_TOKEN_FILE,
    SMTP_USER
)

# Google Calendar API scopes
SCOPES = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
]


class GoogleCalendarService:
    """Handles Google Calendar operations including Google Meet creation"""
    
    def __init__(self):
        self.credentials: Optional[Credentials] = None
        self.service = None
        self.is_configured = False
        self._initialize()
    
    def _initialize(self):
        """Initialize Google Calendar credentials"""
        if not GOOGLE_CALENDAR_CREDENTIALS_FILE:
            print("⚠️ Google Calendar credentials file not configured")
            return
        
        credentials_path = Path(GOOGLE_CALENDAR_CREDENTIALS_FILE)
        if not credentials_path.exists():
            print(f"⚠️ Credentials file not found: {credentials_path}")
            return
        
        try:
            self.credentials = self._get_credentials()
            if self.credentials:
                self.service = build('calendar', 'v3', credentials=self.credentials)
                self.is_configured = True
                print("✅ Google Calendar service initialized")
        except Exception as e:
            print(f"❌ Failed to initialize Google Calendar: {e}")
    
    def _get_credentials(self) -> Optional[Credentials]:
        """Get or refresh Google OAuth credentials"""
        creds = None
        
        # Check for existing token
        token_path = Path(GOOGLE_CALENDAR_TOKEN_FILE) if GOOGLE_CALENDAR_TOKEN_FILE else Path("token.pickle")
        
        if token_path.exists():
            with open(token_path, 'rb') as token:
                creds = pickle.load(token)
        
        # Refresh or get new credentials
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                try:
                    creds.refresh(Request())
                except Exception:
                    creds = self._run_oauth_flow()
            else:
                creds = self._run_oauth_flow()
            
            # Save credentials
            if creds:
                with open(token_path, 'wb') as token:
                    pickle.dump(creds, token)
        
        return creds
    
    def _run_oauth_flow(self) -> Optional[Credentials]:
        """Run OAuth flow to get new credentials"""
        try:
            flow = InstalledAppFlow.from_client_secrets_file(
                GOOGLE_CALENDAR_CREDENTIALS_FILE, 
                SCOPES
            )
            # Run local server for OAuth callback
            creds = flow.run_local_server(port=0)
            return creds
        except Exception as e:
            print(f"❌ OAuth flow failed: {e}")
            return None
    
    def create_event_with_meet(
        self,
        title: str,
        start_time: datetime,
        end_time: Optional[datetime] = None,
        description: str = "",
        attendees: Optional[List[str]] = None,
        send_notifications: bool = True,
        reminder_minutes: int = 60
    ) -> Dict[str, Any]:
        """
        Create a Google Calendar event with Google Meet
        
        Args:
            title: Event title
            start_time: Event start time
            end_time: Event end time (defaults to 1 hour after start)
            description: Event description
            attendees: List of email addresses to invite
            send_notifications: Whether to send email invitations
            reminder_minutes: Minutes before event for reminder
            
        Returns:
            Dict with event details including Meet link
        """
        if not self.is_configured:
            return {
                "success": False,
                "error": "Google Calendar not configured. Please set up OAuth credentials."
            }
        
        try:
            # Default end time to 1 hour after start
            if not end_time:
                end_time = start_time + timedelta(hours=1)
            
            # Build event object
            event = {
                'summary': title,
                'description': description,
                'start': {
                    'dateTime': start_time.isoformat(),
                    'timeZone': 'Europe/Bucharest',
                },
                'end': {
                    'dateTime': end_time.isoformat(),
                    'timeZone': 'Europe/Bucharest',
                },
                'reminders': {
                    'useDefault': False,
                    'overrides': [
                        {'method': 'email', 'minutes': reminder_minutes},
                        {'method': 'popup', 'minutes': 10},
                    ],
                },
                # Enable Google Meet
                'conferenceData': {
                    'createRequest': {
                        'requestId': f"meet-{datetime.now().timestamp()}",
                        'conferenceSolutionKey': {
                            'type': 'hangoutsMeet'
                        }
                    }
                },
            }
            
            # Add attendees if provided (always include the organizer/user email)
            all_attendees = []
            
            # Add organizer's email (SMTP_USER) so they receive invitation too
            if SMTP_USER:
                all_attendees.append({'email': SMTP_USER})
            
            # Add other attendees
            if attendees:
                for email in attendees:
                    # Avoid duplicates
                    if email != SMTP_USER:
                        all_attendees.append({'email': email})
            
            if all_attendees:
                event['attendees'] = all_attendees
            
            # Create event with conference data
            created_event = self.service.events().insert(
                calendarId='primary',
                body=event,
                conferenceDataVersion=1,
                sendUpdates='all' if send_notifications else 'none'
            ).execute()
            
            # Extract Meet link
            meet_link = None
            if 'conferenceData' in created_event:
                entry_points = created_event['conferenceData'].get('entryPoints', [])
                for entry in entry_points:
                    if entry.get('entryPointType') == 'video':
                        meet_link = entry.get('uri')
                        break
            
            return {
                "success": True,
                "event_id": created_event.get('id'),
                "event_link": created_event.get('htmlLink'),
                "meet_link": meet_link,
                "title": title,
                "start_time": start_time.isoformat(),
                "end_time": end_time.isoformat(),
                "attendees": attendees or [],
                "message": f"Evenimentul '{title}' a fost creat cu Google Meet."
            }
            
        except HttpError as e:
            error_details = json.loads(e.content.decode())
            return {
                "success": False,
                "error": f"Google Calendar error: {error_details.get('error', {}).get('message', str(e))}"
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to create event: {str(e)}"
            }
    
    def get_upcoming_events(self, max_results: int = 10) -> Dict[str, Any]:
        """Get upcoming calendar events"""
        if not self.is_configured:
            return {
                "success": False,
                "error": "Google Calendar not configured."
            }
        
        try:
            now = datetime.utcnow().isoformat() + 'Z'
            
            events_result = self.service.events().list(
                calendarId='primary',
                timeMin=now,
                maxResults=max_results,
                singleEvents=True,
                orderBy='startTime'
            ).execute()
            
            events = events_result.get('items', [])
            
            event_list = []
            for event in events:
                start = event['start'].get('dateTime', event['start'].get('date'))
                
                # Extract Meet link if exists
                meet_link = None
                if 'conferenceData' in event:
                    entry_points = event['conferenceData'].get('entryPoints', [])
                    for entry in entry_points:
                        if entry.get('entryPointType') == 'video':
                            meet_link = entry.get('uri')
                            break
                
                event_list.append({
                    "id": event['id'],
                    "title": event.get('summary', 'No title'),
                    "start": start,
                    "end": event['end'].get('dateTime', event['end'].get('date')),
                    "description": event.get('description', ''),
                    "meet_link": meet_link,
                    "attendees": [a.get('email') for a in event.get('attendees', [])],
                    "link": event.get('htmlLink')
                })
            
            return {
                "success": True,
                "count": len(event_list),
                "events": event_list
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get events: {str(e)}"
            }
    
    def delete_event(self, event_id: str) -> Dict[str, Any]:
        """Delete a calendar event"""
        if not self.is_configured:
            return {
                "success": False,
                "error": "Google Calendar not configured."
            }
        
        try:
            self.service.events().delete(
                calendarId='primary',
                eventId=event_id,
                sendUpdates='all'
            ).execute()
            
            return {
                "success": True,
                "message": "Evenimentul a fost șters."
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to delete event: {str(e)}"
            }
    
    def update_event(
        self,
        event_id: str,
        title: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        description: Optional[str] = None
    ) -> Dict[str, Any]:
        """Update an existing calendar event"""
        if not self.is_configured:
            return {
                "success": False,
                "error": "Google Calendar not configured."
            }
        
        try:
            # Get existing event
            event = self.service.events().get(
                calendarId='primary',
                eventId=event_id
            ).execute()
            
            # Update fields
            if title:
                event['summary'] = title
            if description:
                event['description'] = description
            if start_time:
                event['start'] = {
                    'dateTime': start_time.isoformat(),
                    'timeZone': 'Europe/Bucharest'
                }
            if end_time:
                event['end'] = {
                    'dateTime': end_time.isoformat(),
                    'timeZone': 'Europe/Bucharest'
                }
            
            updated_event = self.service.events().update(
                calendarId='primary',
                eventId=event_id,
                body=event,
                sendUpdates='all'
            ).execute()
            
            return {
                "success": True,
                "event_id": updated_event['id'],
                "message": "Evenimentul a fost actualizat."
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to update event: {str(e)}"
            }


# Singleton instance
calendar_service = GoogleCalendarService()

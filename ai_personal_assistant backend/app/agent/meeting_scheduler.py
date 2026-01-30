"""
Meeting Scheduler Service
Handles scheduling meetings with invitations, reminders, and email notifications
"""
import asyncio
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.date import DateTrigger

from app.agent.calendar_service import calendar_service
from app.agent.email_service import email_service
from app.config import SMTP_USER


class MeetingSchedulerService:
    """Handles meeting scheduling with Google Meet and email notifications"""
    
    def __init__(self):
        self.scheduler = AsyncIOScheduler()
        self.scheduled_reminders: Dict[str, str] = {}  # event_id -> job_id
        self._started = False
    
    def start(self):
        """Start the scheduler"""
        if not self._started:
            self.scheduler.start()
            self._started = True
            print("✅ Meeting scheduler started")
    
    def stop(self):
        """Stop the scheduler"""
        if self._started:
            self.scheduler.shutdown()
            self._started = False
            print("⏹️ Meeting scheduler stopped")
    
    def schedule_meeting(
        self,
        title: str,
        start_time: datetime,
        end_time: Optional[datetime] = None,
        attendee_email: Optional[str] = None,
        attendee_name: str = "",
        description: str = "",
        reminder_hours_before: float = 1.0
    ) -> Dict[str, Any]:
        """
        Schedule a meeting with Google Meet and email notifications
        
        Args:
            title: Meeting title
            start_time: When the meeting starts
            end_time: When the meeting ends (default: 1 hour after start)
            attendee_email: Email of the person to invite
            attendee_name: Name of the person to invite
            description: Meeting description
            reminder_hours_before: Hours before meeting to send reminder
            
        Returns:
            Dict with meeting details
        """
        try:
            # Collect attendees
            attendees = []
            if attendee_email:
                attendees.append(attendee_email)
            
            # Add owner email if configured
            if SMTP_USER:
                attendees.append(SMTP_USER)
            
            # Default end time
            if not end_time:
                end_time = start_time + timedelta(hours=1)
            
            # Create calendar event with Google Meet
            result = calendar_service.create_event_with_meet(
                title=title,
                start_time=start_time,
                end_time=end_time,
                description=description,
                attendees=attendees,
                send_notifications=True,
                reminder_minutes=int(reminder_hours_before * 60)
            )
            
            if not result["success"]:
                return result
            
            meet_link = result.get("meet_link", "")
            event_id = result.get("event_id", "")
            
            # Send invitation email to attendee
            if attendee_email:
                self._send_invitation_email(
                    to_email=attendee_email,
                    attendee_name=attendee_name,
                    title=title,
                    start_time=start_time,
                    end_time=end_time,
                    meet_link=meet_link,
                    description=description
                )
            
            # Send confirmation email to organizer (yourself)
            if SMTP_USER:
                self._send_organizer_confirmation_email(
                    title=title,
                    start_time=start_time,
                    end_time=end_time,
                    meet_link=meet_link,
                    attendee_email=attendee_email,
                    attendee_name=attendee_name,
                    description=description
                )
            
            # Schedule reminder emails
            reminder_time = start_time - timedelta(hours=reminder_hours_before)
            if reminder_time > datetime.now():
                self._schedule_reminder(
                    event_id=event_id,
                    reminder_time=reminder_time,
                    title=title,
                    start_time=start_time,
                    meet_link=meet_link,
                    attendee_email=attendee_email,
                    attendee_name=attendee_name
                )
            
            return {
                "success": True,
                "event_id": event_id,
                "meet_link": meet_link,
                "event_link": result.get("event_link"),
                "title": title,
                "start_time": start_time.isoformat(),
                "end_time": end_time.isoformat(),
                "attendee": attendee_email,
                "reminder_scheduled": reminder_time > datetime.now(),
                "reminder_time": reminder_time.isoformat() if reminder_time > datetime.now() else None,
                "message": f"Întâlnirea '{title}' a fost programată cu succes. Link Google Meet: {meet_link}"
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to schedule meeting: {str(e)}"
            }
    
    def _send_invitation_email(
        self,
        to_email: str,
        attendee_name: str,
        title: str,
        start_time: datetime,
        end_time: datetime,
        meet_link: str,
        description: str = ""
    ) -> Dict[str, Any]:
        """Send meeting invitation email"""
        formatted_date = start_time.strftime("%d %B %Y")
        formatted_time = start_time.strftime("%H:%M")
        end_formatted = end_time.strftime("%H:%M")
        
        greeting = f"Dragă {attendee_name}," if attendee_name else "Bună ziua,"
        
        subject = f"Invitație la întâlnire: {title}"
        
        body = f"""
{greeting}

Ai fost invitat(ă) la o întâlnire!

📅 Detalii întâlnire:
• Titlu: {title}
• Data: {formatted_date}
• Ora: {formatted_time} - {end_formatted}

🔗 Link Google Meet:
{meet_link}

{f"📝 Descriere: {description}" if description else ""}

Te rog să confirmi participarea ta răspunzând la acest email.

Cu respect,
Asistentul Personal AI
        """.strip()
        
        html_body = f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #4285f4, #34a853); color: white; padding: 20px; border-radius: 10px 10px 0 0; }}
        .content {{ background: #f9f9f9; padding: 20px; border-radius: 0 0 10px 10px; }}
        .meet-button {{ display: inline-block; background: #4285f4; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; margin: 15px 0; }}
        .details {{ background: white; padding: 15px; border-radius: 8px; margin: 15px 0; }}
        .icon {{ font-size: 1.2em; margin-right: 8px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>📅 Invitație la întâlnire</h2>
        </div>
        <div class="content">
            <p>{greeting}</p>
            <p>Ai fost invitat(ă) la o întâlnire!</p>
            
            <div class="details">
                <p><span class="icon">📌</span><strong>Titlu:</strong> {title}</p>
                <p><span class="icon">📅</span><strong>Data:</strong> {formatted_date}</p>
                <p><span class="icon">⏰</span><strong>Ora:</strong> {formatted_time} - {end_formatted}</p>
                {f'<p><span class="icon">📝</span><strong>Descriere:</strong> {description}</p>' if description else ''}
            </div>
            
            <p><a href="{meet_link}" class="meet-button">🎥 Intră în Google Meet</a></p>
            
            <p>Te rog să confirmi participarea ta răspunzând la acest email.</p>
            
            <p>Cu respect,<br>Asistentul Personal AI</p>
        </div>
    </div>
</body>
</html>
        """
        
        return email_service.send_email(
            to_email=to_email,
            subject=subject,
            body=html_body,
            is_html=True
        )
    
    def _send_organizer_confirmation_email(
        self,
        title: str,
        start_time: datetime,
        end_time: datetime,
        meet_link: str,
        attendee_email: Optional[str],
        attendee_name: str = "",
        description: str = ""
    ) -> Dict[str, Any]:
        """Send confirmation email to the organizer (yourself)"""
        formatted_date = start_time.strftime("%d %B %Y")
        formatted_time = start_time.strftime("%H:%M")
        end_formatted = end_time.strftime("%H:%M")
        
        attendee_info = ""
        if attendee_email:
            if attendee_name:
                attendee_info = f"{attendee_name} ({attendee_email})"
            else:
                attendee_info = attendee_email
        
        subject = f"✅ Întâlnire programată: {title}"
        
        html_body = f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #34a853, #4285f4); color: white; padding: 20px; border-radius: 10px 10px 0 0; }}
        .content {{ background: #f9f9f9; padding: 20px; border-radius: 0 0 10px 10px; }}
        .meet-button {{ display: inline-block; background: #4285f4; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; margin: 15px 0; }}
        .details {{ background: white; padding: 15px; border-radius: 8px; margin: 15px 0; }}
        .icon {{ font-size: 1.2em; margin-right: 8px; }}
        .success {{ color: #34a853; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>✅ Întâlnire programată cu succes!</h2>
        </div>
        <div class="content">
            <p>Salut!</p>
            <p class="success">Întâlnirea ta a fost creată și invitația a fost trimisă.</p>
            
            <div class="details">
                <p><span class="icon">📌</span><strong>Titlu:</strong> {title}</p>
                <p><span class="icon">📅</span><strong>Data:</strong> {formatted_date}</p>
                <p><span class="icon">⏰</span><strong>Ora:</strong> {formatted_time} - {end_formatted}</p>
                {f'<p><span class="icon">👤</span><strong>Participant:</strong> {attendee_info}</p>' if attendee_info else ''}
                {f'<p><span class="icon">📝</span><strong>Descriere:</strong> {description}</p>' if description else ''}
            </div>
            
            <p><a href="{meet_link}" class="meet-button">🎥 Link Google Meet</a></p>
            
            <p>Evenimentul a fost adăugat și în Google Calendar.</p>
            
            <p>Cu respect,<br>Asistentul Personal AI</p>
        </div>
    </div>
</body>
</html>
        """
        
        return email_service.send_email(
            to_email=SMTP_USER,
            subject=subject,
            body=html_body,
            is_html=True
        )
    
    def _schedule_reminder(
        self,
        event_id: str,
        reminder_time: datetime,
        title: str,
        start_time: datetime,
        meet_link: str,
        attendee_email: Optional[str],
        attendee_name: str = ""
    ):
        """Schedule reminder emails"""
        if not self._started:
            self.start()
        
        # Schedule reminder for owner
        if SMTP_USER:
            job_id_owner = f"reminder_{event_id}_owner"
            self.scheduler.add_job(
                self._send_reminder_email,
                trigger=DateTrigger(run_date=reminder_time),
                args=[SMTP_USER, "", title, start_time, meet_link, True],
                id=job_id_owner,
                replace_existing=True
            )
        
        # Schedule reminder for attendee
        if attendee_email and attendee_email != SMTP_USER:
            job_id_attendee = f"reminder_{event_id}_attendee"
            self.scheduler.add_job(
                self._send_reminder_email,
                trigger=DateTrigger(run_date=reminder_time),
                args=[attendee_email, attendee_name, title, start_time, meet_link, False],
                id=job_id_attendee,
                replace_existing=True
            )
        
        self.scheduled_reminders[event_id] = f"reminder_{event_id}"
        print(f"📧 Reminder scheduled for {reminder_time.isoformat()}")
    
    def _send_reminder_email(
        self,
        to_email: str,
        name: str,
        title: str,
        start_time: datetime,
        meet_link: str,
        is_owner: bool
    ):
        """Send reminder email 1 hour before meeting"""
        formatted_time = start_time.strftime("%H:%M")
        formatted_date = start_time.strftime("%d %B %Y")
        
        if is_owner:
            greeting = "Salut!"
            reminder_text = "Ai o întâlnire programată în curând!"
        else:
            greeting = f"Dragă {name}," if name else "Bună ziua,"
            reminder_text = "Îți reamintim despre întâlnirea programată!"
        
        subject = f"⏰ Reminder: {title} - în 1 oră"
        
        body = f"""
{greeting}

{reminder_text}

📅 Detalii întâlnire:
• Titlu: {title}
• Data: {formatted_date}
• Ora: {formatted_time}

🔗 Link Google Meet:
{meet_link}

Te așteptăm!

Cu respect,
Asistentul Personal AI
        """.strip()
        
        html_body = f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #ea4335, #fbbc04); color: white; padding: 20px; border-radius: 10px 10px 0 0; }}
        .content {{ background: #f9f9f9; padding: 20px; border-radius: 0 0 10px 10px; }}
        .meet-button {{ display: inline-block; background: #4285f4; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; margin: 15px 0; }}
        .details {{ background: white; padding: 15px; border-radius: 8px; margin: 15px 0; }}
        .urgent {{ background: #fef7e0; border-left: 4px solid #fbbc04; padding: 10px 15px; margin: 15px 0; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>⏰ Reminder - Întâlnire în 1 oră!</h2>
        </div>
        <div class="content">
            <p>{greeting}</p>
            
            <div class="urgent">
                <strong>🔔 {reminder_text}</strong>
            </div>
            
            <div class="details">
                <p>📌 <strong>Titlu:</strong> {title}</p>
                <p>📅 <strong>Data:</strong> {formatted_date}</p>
                <p>⏰ <strong>Ora:</strong> {formatted_time}</p>
            </div>
            
            <p><a href="{meet_link}" class="meet-button">🎥 Intră în Google Meet</a></p>
            
            <p>Te așteptăm!</p>
            
            <p>Cu respect,<br>Asistentul Personal AI</p>
        </div>
    </div>
</body>
</html>
        """
        
        result = email_service.send_email(
            to_email=to_email,
            subject=subject,
            body=html_body,
            is_html=True
        )
        
        if result["success"]:
            print(f"✅ Reminder sent to {to_email}")
        else:
            print(f"❌ Failed to send reminder to {to_email}: {result.get('error')}")
    
    def cancel_reminder(self, event_id: str) -> bool:
        """Cancel scheduled reminders for an event"""
        try:
            job_id_owner = f"reminder_{event_id}_owner"
            job_id_attendee = f"reminder_{event_id}_attendee"
            
            try:
                self.scheduler.remove_job(job_id_owner)
            except:
                pass
            
            try:
                self.scheduler.remove_job(job_id_attendee)
            except:
                pass
            
            if event_id in self.scheduled_reminders:
                del self.scheduled_reminders[event_id]
            
            return True
        except Exception as e:
            print(f"Error cancelling reminder: {e}")
            return False


# Singleton instance
meeting_scheduler = MeetingSchedulerService()

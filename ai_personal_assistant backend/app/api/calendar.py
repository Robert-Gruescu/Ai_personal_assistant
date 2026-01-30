"""
Calendar API Endpoints
Handles calendar events, meetings, and Google Meet scheduling
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional, List
from pydantic import BaseModel, EmailStr
from datetime import datetime

from app.db.database import get_db
from app.db.models import CalendarEvent, AgentAction
from app.agent.calendar_service import calendar_service
from app.agent.meeting_scheduler import meeting_scheduler

router = APIRouter()


class MeetingRequest(BaseModel):
    """Request model for scheduling a meeting"""
    title: str
    start_time: datetime
    end_time: Optional[datetime] = None
    description: Optional[str] = ""
    attendee_email: Optional[str] = None
    attendee_name: Optional[str] = ""
    reminder_hours_before: float = 1.0


class EventResponse(BaseModel):
    """Response model for calendar events"""
    id: int
    google_event_id: Optional[str]
    title: str
    start_time: datetime
    end_time: datetime
    meet_link: Optional[str]
    attendee_email: Optional[str]
    status: str


@router.post("/schedule-meeting")
async def schedule_meeting(request: MeetingRequest, db: Session = Depends(get_db)):
    """
    Schedule a meeting with Google Meet and email invitations
    
    This endpoint will:
    1. Create a Google Calendar event with Google Meet link
    2. Send invitation email to the attendee
    3. Schedule reminder emails for 1 hour before the meeting
    """
    # Validate start time is in the future
    if request.start_time <= datetime.now():
        raise HTTPException(status_code=400, detail="Start time must be in the future")
    
    # Schedule the meeting
    result = meeting_scheduler.schedule_meeting(
        title=request.title,
        start_time=request.start_time,
        end_time=request.end_time,
        attendee_email=request.attendee_email,
        attendee_name=request.attendee_name or "",
        description=request.description or "",
        reminder_hours_before=request.reminder_hours_before
    )
    
    if not result["success"]:
        # Log failed action
        action = AgentAction(
            action_type="schedule_meeting",
            target=request.attendee_email,
            content=f"Meeting: {request.title}",
            status="failed"
        )
        db.add(action)
        db.commit()
        raise HTTPException(status_code=500, detail=result["error"])
    
    # Save event to local database
    calendar_event = CalendarEvent(
        google_event_id=result.get("event_id"),
        title=request.title,
        description=request.description,
        start_time=request.start_time,
        end_time=request.end_time or request.start_time,
        meet_link=result.get("meet_link"),
        attendee_email=request.attendee_email,
        attendee_name=request.attendee_name,
        reminder_time=datetime.fromisoformat(result["reminder_time"]) if result.get("reminder_time") else None,
        status="scheduled"
    )
    db.add(calendar_event)
    
    # Log successful action
    action = AgentAction(
        action_type="schedule_meeting",
        target=request.attendee_email,
        content=f"Meeting: {request.title}, Meet: {result.get('meet_link')}",
        status="completed",
        executed_at=datetime.utcnow()
    )
    db.add(action)
    db.commit()
    db.refresh(calendar_event)
    
    return {
        "success": True,
        "event_id": calendar_event.id,
        "google_event_id": result.get("event_id"),
        "meet_link": result.get("meet_link"),
        "event_link": result.get("event_link"),
        "title": request.title,
        "start_time": request.start_time.isoformat(),
        "end_time": (request.end_time or request.start_time).isoformat(),
        "attendee": request.attendee_email,
        "message": result.get("message")
    }


@router.get("/events")
async def get_events(
    limit: int = 20,
    include_past: bool = False,
    db: Session = Depends(get_db)
):
    """Get calendar events from local database"""
    query = db.query(CalendarEvent)
    
    if not include_past:
        query = query.filter(CalendarEvent.start_time >= datetime.now())
    
    events = query.filter(
        CalendarEvent.status != "cancelled"
    ).order_by(CalendarEvent.start_time.asc()).limit(limit).all()
    
    return {
        "count": len(events),
        "events": [
            {
                "id": event.id,
                "google_event_id": event.google_event_id,
                "title": event.title,
                "description": event.description,
                "start_time": event.start_time.isoformat(),
                "end_time": event.end_time.isoformat(),
                "meet_link": event.meet_link,
                "attendee_email": event.attendee_email,
                "attendee_name": event.attendee_name,
                "status": event.status
            }
            for event in events
        ]
    }


@router.get("/upcoming")
async def get_upcoming_from_google():
    """Get upcoming events directly from Google Calendar"""
    result = calendar_service.get_upcoming_events(max_results=10)
    
    if not result["success"]:
        raise HTTPException(status_code=500, detail=result["error"])
    
    return result


@router.delete("/events/{event_id}")
async def cancel_event(event_id: int, db: Session = Depends(get_db)):
    """Cancel a calendar event"""
    event = db.query(CalendarEvent).filter(CalendarEvent.id == event_id).first()
    
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    
    # Cancel in Google Calendar if we have the Google event ID
    if event.google_event_id:
        result = calendar_service.delete_event(event.google_event_id)
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result["error"])
    
    # Cancel reminders
    if event.google_event_id:
        meeting_scheduler.cancel_reminder(event.google_event_id)
    
    # Update local database
    event.status = "cancelled"
    event.updated_at = datetime.utcnow()
    db.commit()
    
    return {
        "success": True,
        "message": f"Evenimentul '{event.title}' a fost anulat."
    }


@router.get("/status")
async def get_calendar_status():
    """Check if Google Calendar is properly configured"""
    return {
        "google_calendar_configured": calendar_service.is_configured,
        "scheduler_running": meeting_scheduler._started,
        "pending_reminders": len(meeting_scheduler.scheduled_reminders)
    }

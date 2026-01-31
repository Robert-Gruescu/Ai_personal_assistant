"""
Action Executor
Handles execution of AI-detected actions (tasks, shopping, emails, calendar, etc.)
"""
from typing import Dict, Any, Optional
from datetime import datetime, timedelta
from sqlalchemy.orm import Session

from app.db.models import Task, ShoppingItem, AgentAction, CalendarEvent
from app.agent.email_service import email_service
from app.agent.calendar_service import calendar_service
from app.agent.meeting_scheduler import meeting_scheduler
from app.ai.search_service import search_service


class ActionExecutor:
    """Executes actions based on AI intent detection"""
    
    def execute(
        self,
        intent: str,
        action_data: Optional[Dict[str, Any]],
        db: Session
    ) -> Dict[str, Any]:
        """
        Execute an action based on detected intent
        
        Args:
            intent: The detected intent type
            action_data: Data for the action
            db: Database session
            
        Returns:
            Dict with action result
        """
        action_handlers = {
            "add_task": self._add_task,
            "list_tasks": self._list_tasks,
            "complete_task": self._complete_task,
            "delete_task": self._delete_task,
            "add_shopping_item": self._add_shopping_item,
            "list_shopping": self._list_shopping,
            "remove_shopping_item": self._remove_shopping_item,
            "send_email": self._send_email,
            "read_emails": self._read_emails,
            "read_last_email": self._read_last_email,
            "search_emails": self._search_emails,
            "summarize_email": self._summarize_email,
            "search_internet": self._search_internet,
            "schedule_meeting": self._schedule_meeting,
            "add_calendar_event": self._add_calendar_event,
            "list_calendar_events": self._list_calendar_events,
            "cancel_calendar_event": self._cancel_calendar_event,
        }
        
        handler = action_handlers.get(intent)
        if handler:
            return handler(action_data or {}, db)
        
        return {"success": False, "error": f"Unknown intent: {intent}"}
    
    # ============ TASK ACTIONS ============
    
    def _add_task(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Add a new task or multiple tasks"""
        try:
            # Check if data is a list (multiple tasks)
            if isinstance(data, list):
                added_tasks = []
                for task_data in data:
                    due_date = None
                    if task_data.get("due_date"):
                        due_date = self._parse_date(task_data["due_date"])
                    
                    task = Task(
                        title=task_data.get("title", "Task fără titlu"),
                        description=task_data.get("description"),
                        due_date=due_date,
                        priority=task_data.get("priority", 1),
                        category=task_data.get("category")
                    )
                    db.add(task)
                    added_tasks.append(task_data.get("title", "Task"))
                
                db.commit()
                
                # Get full list after adding
                all_tasks = db.query(Task).filter(Task.is_completed == False).all()
                all_task_titles = [t.title for t in all_tasks]
                
                return {
                    "success": True,
                    "action": "add_task",
                    "count": len(added_tasks),
                    "message": f"Am adăugat {len(added_tasks)} task-uri: {', '.join(added_tasks)}.",
                    "full_list": all_task_titles,
                    "total_tasks": len(all_task_titles)
                }
            
            # Single task
            due_date = None
            if data.get("due_date"):
                due_date = self._parse_date(data["due_date"])
            
            task = Task(
                title=data.get("title", "Task fără titlu"),
                description=data.get("description"),
                due_date=due_date,
                priority=data.get("priority", 1),
                category=data.get("category")
            )
            
            db.add(task)
            db.commit()
            db.refresh(task)
            
            # Get full list after adding
            all_tasks = db.query(Task).filter(Task.is_completed == False).all()
            all_task_titles = [t.title for t in all_tasks]
            
            return {
                "success": True,
                "action": "add_task",
                "task_id": task.id,
                "message": f"Task-ul '{task.title}' a fost adăugat.",
                "full_list": all_task_titles,
                "total_tasks": len(all_task_titles)
            }
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    def _list_tasks(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """List all tasks or filter by criteria"""
        try:
            query = db.query(Task).filter(Task.is_completed == False)
            
            # Filter by category if provided
            if data.get("category"):
                query = query.filter(Task.category == data["category"])
            
            # Filter by date range
            if data.get("today"):
                today = datetime.now().date()
                tomorrow = today + timedelta(days=1)
                query = query.filter(Task.due_date >= today, Task.due_date < tomorrow)
            
            tasks = query.order_by(Task.due_date.asc().nullsfirst()).all()
            
            task_list = []
            for task in tasks:
                task_list.append({
                    "id": task.id,
                    "title": task.title,
                    "description": task.description,
                    "due_date": task.due_date.isoformat() if task.due_date else None,
                    "priority": task.priority,
                    "category": task.category
                })
            
            return {
                "success": True,
                "action": "list_tasks",
                "count": len(task_list),
                "tasks": task_list
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _complete_task(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Mark a task as completed"""
        try:
            task = None
            
            if data.get("task_id"):
                task = db.query(Task).filter(Task.id == data["task_id"]).first()
            elif data.get("task_title"):
                task = db.query(Task).filter(
                    Task.title.ilike(f"%{data['task_title']}%")
                ).first()
            
            if not task:
                return {"success": False, "error": "Task-ul nu a fost găsit."}
            
            task.is_completed = True
            task.updated_at = datetime.utcnow()
            db.commit()
            
            return {
                "success": True,
                "action": "complete_task",
                "message": f"Task-ul '{task.title}' a fost marcat ca finalizat."
            }
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    def _delete_task(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Delete a task"""
        try:
            task = None
            
            if data.get("task_id"):
                task = db.query(Task).filter(Task.id == data["task_id"]).first()
            elif data.get("task_title"):
                task = db.query(Task).filter(
                    Task.title.ilike(f"%{data['task_title']}%")
                ).first()
            
            if not task:
                return {"success": False, "error": "Task-ul nu a fost găsit."}
            
            title = task.title
            db.delete(task)
            db.commit()
            
            return {
                "success": True,
                "action": "delete_task",
                "message": f"Task-ul '{title}' a fost șters."
            }
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    # ============ SHOPPING ACTIONS ============
    
    def _add_shopping_item(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Add item or multiple items to shopping list"""
        try:
            # Check if data is a list (multiple items)
            if isinstance(data, list):
                added_items = []
                for item_data in data:
                    item = ShoppingItem(
                        name=item_data.get("name", "Item"),
                        quantity=str(item_data.get("quantity", "1")) if item_data.get("quantity") else "1",
                        category=item_data.get("category"),
                        notes=item_data.get("notes"),
                        price_estimate=item_data.get("price")
                    )
                    db.add(item)
                    added_items.append(item_data.get("name", "Item"))
                
                db.commit()
                
                # Get full list after adding
                all_items = db.query(ShoppingItem).filter(ShoppingItem.is_purchased == False).all()
                all_item_names = [i.name for i in all_items]
                
                return {
                    "success": True,
                    "action": "add_shopping_item",
                    "count": len(added_items),
                    "message": f"Am adăugat {len(added_items)} produse pe listă: {', '.join(added_items)}.",
                    "full_list": all_item_names,
                    "total_items": len(all_item_names)
                }
            
            # Single item
            item = ShoppingItem(
                name=data.get("name", "Item"),
                quantity=str(data.get("quantity", "1")) if data.get("quantity") else "1",
                category=data.get("category"),
                notes=data.get("notes"),
                price_estimate=data.get("price")
            )
            
            db.add(item)
            db.commit()
            db.refresh(item)
            
            # Get full list after adding
            all_items = db.query(ShoppingItem).filter(ShoppingItem.is_purchased == False).all()
            all_item_names = [i.name for i in all_items]
            
            return {
                "success": True,
                "action": "add_shopping_item",
                "item_id": item.id,
                "message": f"'{item.name}' a fost adăugat la lista de cumpărături.",
                "full_list": all_item_names,
                "total_items": len(all_item_names)
            }
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    def _list_shopping(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """List shopping items"""
        try:
            query = db.query(ShoppingItem).filter(ShoppingItem.is_purchased == False)
            
            if data.get("category"):
                query = query.filter(ShoppingItem.category == data["category"])
            
            items = query.all()
            
            item_list = []
            for item in items:
                item_list.append({
                    "id": item.id,
                    "name": item.name,
                    "quantity": item.quantity,
                    "category": item.category,
                    "notes": item.notes,
                    "price_estimate": item.price_estimate
                })
            
            return {
                "success": True,
                "action": "list_shopping",
                "count": len(item_list),
                "items": item_list
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _remove_shopping_item(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Remove or mark as purchased"""
        try:
            item = None
            
            if data.get("item_id"):
                item = db.query(ShoppingItem).filter(ShoppingItem.id == data["item_id"]).first()
            elif data.get("item_name"):
                # Normalize search term - remove common Romanian suffixes and endings
                search_term = data['item_name'].lower().strip()
                # Remove common suffixes: -le, -ul, -a, -ele, -urile, -ii
                for suffix in ['urile', 'ele', 'ule', 'ul', 'le', 'ii', 'a']:
                    if search_term.endswith(suffix) and len(search_term) > len(suffix) + 2:
                        search_term = search_term[:-len(suffix)]
                        break
                
                # First try exact match on normalized term
                item = db.query(ShoppingItem).filter(
                    ShoppingItem.name.ilike(f"%{search_term}%")
                ).filter(ShoppingItem.is_purchased == False).first()
                
                # If not found, try with original term
                if not item:
                    item = db.query(ShoppingItem).filter(
                        ShoppingItem.name.ilike(f"%{data['item_name']}%")
                    ).filter(ShoppingItem.is_purchased == False).first()
            
            if not item:
                return {"success": False, "error": "Produsul nu a fost găsit pe listă."}
            
            name = item.name
            
            # Mark as purchased or delete
            if data.get("purchased", False):
                item.is_purchased = True
                db.commit()
                return {
                    "success": True,
                    "action": "mark_purchased",
                    "message": f"'{name}' a fost marcat ca cumpărat."
                }
            else:
                db.delete(item)
                db.commit()
                return {
                    "success": True,
                    "action": "remove_shopping_item",
                    "message": f"'{name}' a fost șters de pe listă."
                }
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    # ============ AGENT ACTIONS ============
    
    def _send_email(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Send an email"""
        try:
            to_email = data.get("to")
            subject = data.get("subject", "Mesaj de la Asistentul AI")
            body = data.get("body", "")
            
            if not to_email:
                return {"success": False, "error": "Adresa de email nu a fost specificată."}
            
            if not email_service.validate_email(to_email):
                return {"success": False, "error": "Adresa de email nu este validă."}
            
            # Log action
            action = AgentAction(
                action_type="email",
                target=to_email,
                content=f"Subject: {subject}\n\n{body}",
                status="pending"
            )
            db.add(action)
            db.commit()
            
            # Send email
            result = email_service.send_email(to_email, subject, body)
            
            # Update action status
            action.status = "completed" if result["success"] else "failed"
            action.executed_at = datetime.utcnow()
            db.commit()
            
            return result
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    def _read_emails(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Read recent emails from inbox"""
        try:
            count = data.get("count", 5)
            result = email_service.get_recent_emails(count)
            
            if not result.get("success"):
                return {"success": False, "error": result.get("error", "Nu am putut citi emailurile")}
            
            emails = result.get("emails", [])
            
            if not emails:
                return {
                    "success": True,
                    "action": "read_emails",
                    "message": "Nu ai emailuri noi în inbox.",
                    "emails": []
                }
            
            # Format emails for response
            email_list = []
            for i, email_item in enumerate(emails, 1):
                email_list.append({
                    "index": i,
                    "from": email_item.get("from", "Necunoscut"),
                    "subject": email_item.get("subject", "Fără subiect"),
                    "date": email_item.get("date", ""),
                    "preview": email_item.get("body", "")[:200] + "..." if len(email_item.get("body", "")) > 200 else email_item.get("body", "")
                })
            
            return {
                "success": True,
                "action": "read_emails",
                "message": f"Ai {len(emails)} emailuri recente.",
                "emails": email_list
            }
        except Exception as e:
            return {"success": False, "error": f"Nu am putut citi emailurile: {str(e)}"}
    
    def _read_last_email(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Read the last email from inbox"""
        try:
            result = email_service.get_recent_emails(1)
            
            if not result.get("success"):
                return {"success": False, "error": result.get("error", "Nu am putut citi emailul")}
            
            emails = result.get("emails", [])
            
            if not emails:
                return {
                    "success": True,
                    "action": "read_last_email",
                    "message": "Nu ai emailuri noi în inbox.",
                    "email": None
                }
            
            email_item = emails[0]
            return {
                "success": True,
                "action": "read_last_email",
                "message": "Am citit ultimul email.",
                "email": {
                    "from": email_item.get("from", "Necunoscut"),
                    "subject": email_item.get("subject", "Fără subiect"),
                    "date": email_item.get("date", ""),
                    "body": email_item.get("body", "")
                }
            }
        except Exception as e:
            return {"success": False, "error": f"Nu am putut citi emailul: {str(e)}"}
    
    def _search_emails(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Search emails by query"""
        try:
            query = data.get("query", "")
            if not query:
                return {"success": False, "error": "Nu ai specificat ce să caut în emailuri."}
            
            result = email_service.search_emails(query)
            
            if not result.get("success"):
                return {"success": False, "error": result.get("error", "Nu am putut căuta emailuri")}
            
            emails = result.get("emails", [])
            
            if not emails:
                return {
                    "success": True,
                    "action": "search_emails",
                    "message": f"Nu am găsit emailuri care să conțină '{query}'.",
                    "emails": []
                }
            
            # Format emails for response
            email_list = []
            for i, email_item in enumerate(emails, 1):
                email_list.append({
                    "index": i,
                    "from": email_item.get("from", "Necunoscut"),
                    "subject": email_item.get("subject", "Fără subiect"),
                    "date": email_item.get("date", ""),
                    "preview": email_item.get("body", "")[:200] + "..." if len(email_item.get("body", "")) > 200 else email_item.get("body", "")
                })
            
            return {
                "success": True,
                "action": "search_emails",
                "message": f"Am găsit {len(emails)} emailuri pentru '{query}'.",
                "emails": email_list
            }
        except Exception as e:
            return {"success": False, "error": f"Nu am putut căuta emailuri: {str(e)}"}
    
    def _summarize_email(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Summarize a specific email"""
        try:
            index = data.get("index", 1)
            result = email_service.get_email_by_index(index)
            
            if not result.get("success"):
                return {
                    "success": False,
                    "error": result.get("error", f"Nu am găsit emailul cu indexul {index}.")
                }
            
            email_item = result.get("email", {})
            
            # Return email content for AI to summarize
            return {
                "success": True,
                "action": "summarize_email",
                "message": "Am citit emailul pentru rezumat.",
                "email": {
                    "from": email_item.get("from", "Necunoscut"),
                    "subject": email_item.get("subject", "Fără subiect"),
                    "date": email_item.get("date", ""),
                    "body": email_item.get("body", "")
                },
                "needs_ai_summary": True
            }
        except Exception as e:
            return {"success": False, "error": f"Nu am putut citi emailul: {str(e)}"}
    
    def _search_internet(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Search the internet for information"""
        try:
            query = data.get("query", "")
            if not query:
                return {"success": False, "error": "Nu ai specificat ce să caut."}
            
            results = search_service.search(query)
            formatted = search_service.format_results_for_ai(results)
            
            return {
                "success": results["success"],
                "action": "search_internet",
                "query": query,
                "results": results.get("results", []),
                "direct_answer": results.get("direct_answer"),
                "formatted": formatted
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    # ============ CALENDAR & MEETING ACTIONS ============
    
    def _schedule_meeting(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Schedule a meeting with Google Meet and email invitations"""
        try:
            title = data.get("title", "Întâlnire")
            
            # Parse start time
            start_time = None
            if data.get("start_time"):
                start_time = self._parse_date(data["start_time"])
            elif data.get("date") and data.get("time"):
                start_time = self._parse_date(f"{data['date']} {data['time']}")
            
            if not start_time:
                return {
                    "success": False, 
                    "error": "Nu am putut determina data și ora întâlnirii."
                }
            
            # Ensure start time is in the future
            if start_time <= datetime.now():
                return {
                    "success": False,
                    "error": "Data întâlnirii trebuie să fie în viitor."
                }
            
            # Parse end time or default to 1 hour
            end_time = None
            duration_minutes = data.get("duration_minutes", 60)
            if data.get("end_time"):
                end_time = self._parse_date(data["end_time"])
            else:
                end_time = start_time + timedelta(minutes=duration_minutes)
            
            attendee_email = data.get("attendee_email")
            attendee_name = data.get("attendee_name", "")
            description = data.get("description", "")
            reminder_hours = data.get("reminder_hours", 1.0)
            
            # Validate email if provided
            if attendee_email and not email_service.validate_email(attendee_email):
                return {
                    "success": False,
                    "error": f"Adresa de email '{attendee_email}' nu este validă."
                }
            
            # Schedule the meeting
            result = meeting_scheduler.schedule_meeting(
                title=title,
                start_time=start_time,
                end_time=end_time,
                attendee_email=attendee_email,
                attendee_name=attendee_name,
                description=description,
                reminder_hours_before=reminder_hours
            )
            
            if result["success"]:
                # Save to local database
                event = CalendarEvent(
                    google_event_id=result.get("event_id"),
                    title=title,
                    description=description,
                    start_time=start_time,
                    end_time=end_time,
                    meet_link=result.get("meet_link"),
                    attendee_email=attendee_email,
                    attendee_name=attendee_name,
                    reminder_time=start_time - timedelta(hours=reminder_hours),
                    status="scheduled"
                )
                db.add(event)
                
                # Log action
                action = AgentAction(
                    action_type="schedule_meeting",
                    target=attendee_email,
                    content=f"Meeting: {title}, Meet: {result.get('meet_link')}",
                    status="completed",
                    executed_at=datetime.utcnow()
                )
                db.add(action)
                db.commit()
                
                return {
                    "success": True,
                    "action": "schedule_meeting",
                    "event_id": result.get("event_id"),
                    "meet_link": result.get("meet_link"),
                    "title": title,
                    "start_time": start_time.isoformat(),
                    "attendee": attendee_email,
                    "message": result.get("message")
                }
            else:
                return result
                
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    def _add_calendar_event(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Add a simple calendar event (without meeting)"""
        try:
            title = data.get("title", "Eveniment")
            
            # Parse date/time
            start_time = None
            if data.get("start_time"):
                start_time = self._parse_date(data["start_time"])
            elif data.get("date"):
                date_str = data["date"]
                time_str = data.get("time", "09:00")
                start_time = self._parse_date(f"{date_str} {time_str}")
            
            if not start_time:
                return {
                    "success": False,
                    "error": "Nu am putut determina data evenimentului."
                }
            
            # End time
            duration_minutes = data.get("duration_minutes", 60)
            end_time = start_time + timedelta(minutes=duration_minutes)
            
            description = data.get("description", "")
            
            # Create in Google Calendar (without Meet)
            result = calendar_service.create_event_with_meet(
                title=title,
                start_time=start_time,
                end_time=end_time,
                description=description,
                attendees=None,
                send_notifications=False
            )
            
            if result["success"]:
                # Save locally
                event = CalendarEvent(
                    google_event_id=result.get("event_id"),
                    title=title,
                    description=description,
                    start_time=start_time,
                    end_time=end_time,
                    status="scheduled"
                )
                db.add(event)
                db.commit()
                
                return {
                    "success": True,
                    "action": "add_calendar_event",
                    "event_id": result.get("event_id"),
                    "title": title,
                    "start_time": start_time.isoformat(),
                    "message": f"Evenimentul '{title}' a fost adăugat în calendar."
                }
            else:
                return result
                
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    def _list_calendar_events(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """List upcoming calendar events"""
        try:
            # Try to get from Google Calendar first
            google_result = calendar_service.get_upcoming_events(max_results=10)
            
            if google_result["success"]:
                events = google_result.get("events", [])
                
                if not events:
                    return {
                        "success": True,
                        "action": "list_calendar_events",
                        "count": 0,
                        "events": [],
                        "message": "Nu ai evenimente programate."
                    }
                
                # Format events for response
                event_list = []
                for event in events:
                    event_info = {
                        "title": event.get("title"),
                        "start": event.get("start"),
                        "end": event.get("end"),
                        "meet_link": event.get("meet_link"),
                        "attendees": event.get("attendees", [])
                    }
                    event_list.append(event_info)
                
                return {
                    "success": True,
                    "action": "list_calendar_events",
                    "count": len(event_list),
                    "events": event_list,
                    "message": f"Ai {len(event_list)} evenimente programate."
                }
            else:
                # Fallback to local database
                events = db.query(CalendarEvent).filter(
                    CalendarEvent.start_time >= datetime.now(),
                    CalendarEvent.status == "scheduled"
                ).order_by(CalendarEvent.start_time.asc()).limit(10).all()
                
                event_list = []
                for event in events:
                    event_list.append({
                        "id": event.id,
                        "title": event.title,
                        "start": event.start_time.isoformat(),
                        "end": event.end_time.isoformat(),
                        "meet_link": event.meet_link,
                        "attendee": event.attendee_email
                    })
                
                return {
                    "success": True,
                    "action": "list_calendar_events",
                    "count": len(event_list),
                    "events": event_list,
                    "message": f"Ai {len(event_list)} evenimente programate."
                }
                
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _cancel_calendar_event(self, data: Dict[str, Any], db: Session) -> Dict[str, Any]:
        """Cancel a calendar event"""
        try:
            event = None
            
            # Find by ID or title
            if data.get("event_id"):
                event = db.query(CalendarEvent).filter(
                    CalendarEvent.id == data["event_id"]
                ).first()
            elif data.get("google_event_id"):
                event = db.query(CalendarEvent).filter(
                    CalendarEvent.google_event_id == data["google_event_id"]
                ).first()
            elif data.get("title"):
                event = db.query(CalendarEvent).filter(
                    CalendarEvent.title.ilike(f"%{data['title']}%"),
                    CalendarEvent.status == "scheduled"
                ).first()
            
            if not event:
                return {
                    "success": False,
                    "error": "Evenimentul nu a fost găsit."
                }
            
            # Cancel in Google Calendar
            if event.google_event_id:
                calendar_service.delete_event(event.google_event_id)
                meeting_scheduler.cancel_reminder(event.google_event_id)
            
            # Update local database
            title = event.title
            event.status = "cancelled"
            event.updated_at = datetime.utcnow()
            db.commit()
            
            return {
                "success": True,
                "action": "cancel_calendar_event",
                "message": f"Evenimentul '{title}' a fost anulat."
            }
            
        except Exception as e:
            db.rollback()
            return {"success": False, "error": str(e)}
    
    # ============ HELPERS ============
    
    def _parse_date(self, date_str: str) -> Optional[datetime]:
        """Parse date string to datetime"""
        from dateutil import parser
        try:
            return parser.parse(date_str, dayfirst=True)
        except:
            return None


# Singleton instance
action_executor = ActionExecutor()

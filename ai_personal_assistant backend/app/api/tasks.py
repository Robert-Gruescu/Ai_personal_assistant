"""
Tasks API Endpoints
Manages user tasks and reminders
"""
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel

from app.db.database import get_db
from app.db.models import Task

router = APIRouter()


class TaskCreate(BaseModel):
    title: str
    description: Optional[str] = None
    due_date: Optional[str] = None
    priority: int = 1
    category: Optional[str] = None


class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    due_date: Optional[str] = None
    priority: Optional[int] = None
    category: Optional[str] = None
    is_completed: Optional[bool] = None


@router.get("/")
async def list_tasks(
    completed: Optional[bool] = None,
    category: Optional[str] = None,
    today: bool = False,
    db: Session = Depends(get_db)
):
    """Get all tasks with optional filters"""
    query = db.query(Task)
    
    if completed is not None:
        query = query.filter(Task.is_completed == completed)
    
    if category:
        query = query.filter(Task.category == category)
    
    if today:
        today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        today_end = today_start + timedelta(days=1)
        query = query.filter(Task.due_date >= today_start, Task.due_date < today_end)
    
    tasks = query.order_by(Task.due_date.asc().nullsfirst()).all()
    
    return {
        "count": len(tasks),
        "tasks": [
            {
                "id": task.id,
                "title": task.title,
                "description": task.description,
                "due_date": task.due_date.isoformat() if task.due_date else None,
                "priority": task.priority,
                "category": task.category,
                "is_completed": task.is_completed,
                "created_at": task.created_at.isoformat()
            }
            for task in tasks
        ]
    }


@router.post("/")
async def create_task(task: TaskCreate, db: Session = Depends(get_db)):
    """Create a new task"""
    due_date = None
    if task.due_date:
        try:
            from dateutil import parser
            due_date = parser.parse(task.due_date)
        except:
            pass
    
    new_task = Task(
        title=task.title,
        description=task.description,
        due_date=due_date,
        priority=task.priority,
        category=task.category
    )
    
    db.add(new_task)
    db.commit()
    db.refresh(new_task)
    
    return {
        "id": new_task.id,
        "title": new_task.title,
        "message": f"Task '{new_task.title}' created successfully"
    }


@router.get("/{task_id}")
async def get_task(task_id: int, db: Session = Depends(get_db)):
    """Get a specific task"""
    task = db.query(Task).filter(Task.id == task_id).first()
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    return {
        "id": task.id,
        "title": task.title,
        "description": task.description,
        "due_date": task.due_date.isoformat() if task.due_date else None,
        "priority": task.priority,
        "category": task.category,
        "is_completed": task.is_completed,
        "created_at": task.created_at.isoformat(),
        "updated_at": task.updated_at.isoformat()
    }


@router.put("/{task_id}")
async def update_task(task_id: int, task_update: TaskUpdate, db: Session = Depends(get_db)):
    """Update a task"""
    task = db.query(Task).filter(Task.id == task_id).first()
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    if task_update.title is not None:
        task.title = task_update.title
    if task_update.description is not None:
        task.description = task_update.description
    if task_update.due_date is not None:
        try:
            from dateutil import parser
            task.due_date = parser.parse(task_update.due_date)
        except:
            pass
    if task_update.priority is not None:
        task.priority = task_update.priority
    if task_update.category is not None:
        task.category = task_update.category
    if task_update.is_completed is not None:
        task.is_completed = task_update.is_completed
    
    task.updated_at = datetime.utcnow()
    db.commit()
    
    return {"success": True, "message": f"Task '{task.title}' updated"}


@router.delete("/{task_id}")
async def delete_task(task_id: int, db: Session = Depends(get_db)):
    """Delete a task"""
    task = db.query(Task).filter(Task.id == task_id).first()
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    title = task.title
    db.delete(task)
    db.commit()
    
    return {"success": True, "message": f"Task '{title}' deleted"}


@router.post("/{task_id}/complete")
async def complete_task(task_id: int, db: Session = Depends(get_db)):
    """Mark a task as completed"""
    task = db.query(Task).filter(Task.id == task_id).first()
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    task.is_completed = True
    task.updated_at = datetime.utcnow()
    db.commit()
    
    return {"success": True, "message": f"Task '{task.title}' marked as completed"}

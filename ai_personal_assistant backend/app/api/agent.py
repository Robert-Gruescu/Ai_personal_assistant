"""
Agent Actions API Endpoints
Handles email sending, internet search, and other agent capabilities
"""
from fastapi import APIRouter, Depends, HTTPException, Form
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel

from app.db.database import get_db
from app.db.models import AgentAction
from app.agent.email_service import email_service
from app.ai.search_service import search_service

router = APIRouter()


class EmailRequest(BaseModel):
    to: str
    subject: str
    body: str


class SearchRequest(BaseModel):
    query: str
    num_results: int = 5


@router.post("/email")
async def send_email(request: EmailRequest, db: Session = Depends(get_db)):
    """Send an email on behalf of the user"""
    # Validate email
    if not email_service.validate_email(request.to):
        raise HTTPException(status_code=400, detail="Invalid email address")
    
    # Log action
    action = AgentAction(
        action_type="email",
        target=request.to,
        content=f"Subject: {request.subject}\n\n{request.body}",
        status="pending"
    )
    db.add(action)
    db.commit()
    
    # Send email
    result = email_service.send_email(request.to, request.subject, request.body)
    
    # Update action status
    action.status = "completed" if result["success"] else "failed"
    from datetime import datetime
    action.executed_at = datetime.utcnow()
    db.commit()
    
    if not result["success"]:
        raise HTTPException(status_code=500, detail=result["error"])
    
    return result


@router.post("/search")
async def search_internet(request: SearchRequest):
    """Search the internet for information"""
    result = search_service.search(request.query, request.num_results)
    
    if not result["success"]:
        raise HTTPException(status_code=500, detail=result["error"])
    
    return result


@router.get("/history")
async def get_action_history(
    action_type: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 20,
    db: Session = Depends(get_db)
):
    """Get history of agent actions"""
    query = db.query(AgentAction)
    
    if action_type:
        query = query.filter(AgentAction.action_type == action_type)
    
    if status:
        query = query.filter(AgentAction.status == status)
    
    actions = query.order_by(AgentAction.created_at.desc()).limit(limit).all()
    
    return {
        "count": len(actions),
        "actions": [
            {
                "id": action.id,
                "type": action.action_type,
                "target": action.target,
                "status": action.status,
                "created_at": action.created_at.isoformat(),
                "executed_at": action.executed_at.isoformat() if action.executed_at else None
            }
            for action in actions
        ]
    }

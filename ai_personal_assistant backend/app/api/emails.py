"""
Email API Endpoints
Handles reading and managing emails
"""
from fastapi import APIRouter, HTTPException, Query
from typing import Optional
from pydantic import BaseModel

from app.agent.email_service import email_service

router = APIRouter()


class EmailSearchRequest(BaseModel):
    """Request model for email search"""
    query: str
    count: int = 5


@router.get("/inbox")
async def get_inbox_emails(
    count: int = Query(default=10, ge=1, le=50, description="Number of emails to fetch")
):
    """
    Get recent emails from inbox
    
    Returns the most recent emails with subject, sender, date and preview
    """
    result = email_service.get_recent_emails(count=count)
    
    if not result["success"]:
        raise HTTPException(status_code=500, detail=result["error"])
    
    return result


@router.get("/inbox/{index}")
async def get_email_by_index(index: int):
    """
    Get a specific email by index
    
    Index 0 = most recent email
    """
    result = email_service.get_email_by_index(index=index)
    
    if not result["success"]:
        raise HTTPException(status_code=404, detail=result["error"])
    
    return result


@router.post("/search")
async def search_emails(request: EmailSearchRequest):
    """
    Search emails by subject, sender or content
    """
    result = email_service.search_emails(query=request.query, count=request.count)
    
    if not result["success"]:
        raise HTTPException(status_code=500, detail=result["error"])
    
    return result


@router.get("/latest")
async def get_latest_email():
    """
    Get the most recent email with full details
    """
    result = email_service.get_email_by_index(index=0)
    
    if not result["success"]:
        raise HTTPException(status_code=500, detail=result["error"])
    
    return result

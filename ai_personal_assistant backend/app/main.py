"""
Main FastAPI Application Entry Point
"""
from fastapi import FastAPI
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.config import DEBUG
from app.db.database import init_db
from app.api import voice, conversations, tasks, shopping, agent, calendar, emails
from app.agent.meeting_scheduler import meeting_scheduler

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database and scheduler on startup"""
    await init_db()
    print("✅ Database initialized")
    
    # Start the meeting scheduler for reminders
    meeting_scheduler.start()
    print("✅ Meeting scheduler started")
    
    print("✅ AI Personal Assistant Backend is running!")
    yield
    
    # Shutdown
    meeting_scheduler.stop()
    print("👋 Shutting down...")

# Create FastAPI app
app = FastAPI(
    title="AI Personal Assistant API",
    description="Voice-based AI Personal Assistant Backend",
    version="1.0.0",
    lifespan=lifespan
)

# CORS - allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app's origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routers
app.include_router(voice.router, prefix="/api/voice", tags=["Voice"])
app.include_router(conversations.router, prefix="/api/conversations", tags=["Conversations"])
app.include_router(tasks.router, prefix="/api/tasks", tags=["Tasks"])
app.include_router(shopping.router, prefix="/api/shopping", tags=["Shopping"])
app.include_router(agent.router, prefix="/api/agent", tags=["Agent Actions"])
app.include_router(calendar.router, prefix="/api/calendar", tags=["Calendar & Meetings"])
app.include_router(emails.router, prefix="/api/emails", tags=["Emails"])

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "online",
        "message": "AI Personal Assistant Backend is running",
        "version": "1.0.0"
    }

@app.get("/health")
async def health_check():
    """Health check for Docker"""
    return {"status": "healthy"}


@app.get("/favicon.ico")
async def favicon():
    """Return empty favicon to prevent 404 errors"""
    return Response(content=b"", media_type="image/x-icon")

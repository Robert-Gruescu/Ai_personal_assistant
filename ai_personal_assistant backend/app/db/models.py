"""
Database Models - SQLAlchemy ORM
"""
from datetime import datetime
from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, Float
from sqlalchemy.orm import relationship
from app.db.database import Base


class Conversation(Base):
    """Stores conversation sessions"""
    __tablename__ = "conversations"
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), default="New Conversation")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    messages = relationship("Message", back_populates="conversation", cascade="all, delete-orphan")


class Message(Base):
    """Stores individual messages in conversations"""
    __tablename__ = "messages"
    
    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(Integer, ForeignKey("conversations.id"), nullable=False)
    role = Column(String(20), nullable=False)  # 'user' or 'assistant'
    content = Column(Text, nullable=False)
    audio_path = Column(String(500), nullable=True)  # Path to audio file if saved
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    conversation = relationship("Conversation", back_populates="messages")


class Task(Base):
    """Stores user tasks with scheduling"""
    __tablename__ = "tasks"
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    due_date = Column(DateTime, nullable=True)
    reminder_date = Column(DateTime, nullable=True)
    is_completed = Column(Boolean, default=False)
    priority = Column(Integer, default=1)  # 1=low, 2=medium, 3=high
    category = Column(String(100), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class ShoppingItem(Base):
    """Stores shopping list items"""
    __tablename__ = "shopping_items"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    quantity = Column(String(50), default="1")
    category = Column(String(100), nullable=True)  # groceries, electronics, etc.
    is_purchased = Column(Boolean, default=False)
    notes = Column(Text, nullable=True)
    price_estimate = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class AgentAction(Base):
    """Logs agent actions (emails sent, messages, etc.)"""
    __tablename__ = "agent_actions"
    
    id = Column(Integer, primary_key=True, index=True)
    action_type = Column(String(50), nullable=False)  # 'email', 'sms', 'reminder'
    target = Column(String(255), nullable=True)  # email address, phone number
    content = Column(Text, nullable=True)
    status = Column(String(20), default="pending")  # pending, completed, failed
    created_at = Column(DateTime, default=datetime.utcnow)
    executed_at = Column(DateTime, nullable=True)


class CalendarEvent(Base):
    """Stores calendar events and meetings"""
    __tablename__ = "calendar_events"
    
    id = Column(Integer, primary_key=True, index=True)
    google_event_id = Column(String(255), nullable=True, index=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)
    meet_link = Column(String(500), nullable=True)
    attendee_email = Column(String(255), nullable=True)
    attendee_name = Column(String(255), nullable=True)
    reminder_sent = Column(Boolean, default=False)
    reminder_time = Column(DateTime, nullable=True)
    status = Column(String(20), default="scheduled")  # scheduled, completed, cancelled
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

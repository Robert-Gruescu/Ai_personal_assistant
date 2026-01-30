"""
Configuration module - loads settings from environment variables
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file
load_dotenv()

# Base paths
BASE_DIR = Path(__file__).resolve().parent.parent
AUDIO_DIR = BASE_DIR / "audio_files"
AUDIO_DIR.mkdir(exist_ok=True)

# API Settings
API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = int(os.getenv("API_PORT", "8000"))
DEBUG = os.getenv("DEBUG", "true").lower() == "true"

# Google Gemini API
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./ai_assistant.db")

# Voice Settings
SPEECH_LANGUAGE = os.getenv("SPEECH_LANGUAGE", "ro-RO")
TTS_VOICE = os.getenv("TTS_VOICE", "ro-RO-Wavenet-A")

# Email Settings (for agent actions)
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")

# IMAP Settings (for reading emails)
IMAP_HOST = os.getenv("IMAP_HOST", "imap.gmail.com")
IMAP_PORT = int(os.getenv("IMAP_PORT", "993"))

# Search API (SerpAPI for internet search)
SERPAPI_KEY = os.getenv("SERPAPI_KEY", "")

# Google Calendar API Settings
GOOGLE_CALENDAR_CREDENTIALS_FILE = os.getenv("GOOGLE_CALENDAR_CREDENTIALS_FILE", "credentials.json")
GOOGLE_CALENDAR_TOKEN_FILE = os.getenv("GOOGLE_CALENDAR_TOKEN_FILE", "token.pickle")

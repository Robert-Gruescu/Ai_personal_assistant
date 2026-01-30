"""
Voice API Endpoints
Handles the complete voice pipeline: audio in -> STT -> AI -> TTS -> audio out
"""
import io
import base64
from datetime import datetime
from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException
from fastapi.responses import Response, JSONResponse
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel


class ChatRequest(BaseModel):
    text: str
    conversation_id: Optional[int] = None

from app.db.database import get_db
from app.db.models import Conversation, Message
from app.voice.speech_to_text import stt_service
from app.voice.text_to_speech import tts_service
from app.ai.gemini_service import gemini_service
from app.ai.search_service import search_service
from app.agent.action_executor import action_executor

router = APIRouter()


@router.post("/process")
async def process_voice(
    audio: UploadFile = File(...),
    conversation_id: Optional[int] = Form(None),
    audio_format: str = Form("wav"),
    db: Session = Depends(get_db)
):
    """
    Main voice processing endpoint.
    
    Flow: Audio input -> Speech-to-Text -> AI Processing -> Text-to-Speech -> Audio output
    
    Args:
        audio: Audio file from Flutter app
        conversation_id: Optional conversation ID for context
        audio_format: Format of uploaded audio (webm, wav, mp3, ogg)
        
    Returns:
        JSON with response text and base64 encoded audio
    """
    try:
        # 1. Read audio file
        audio_bytes = await audio.read()
        
        if not audio_bytes:
            raise HTTPException(status_code=400, detail="Empty audio file")
        
        print(f"📥 Received audio: {len(audio_bytes)} bytes, format: {audio_format}")
        
        # 2. Speech-to-Text
        stt_result = stt_service.transcribe(audio_bytes, audio_format)
        
        if not stt_result["success"]:
            # Return error with TTS
            error_message = "Nu am înțeles ce ai spus. Poți repeta mai clar?"
            tts_result = tts_service.synthesize(error_message)
            
            return JSONResponse({
                "success": False,
                "transcription": "",
                "user_text": "",
                "response": error_message,
                "response_text": error_message,
                "audio": base64.b64encode(tts_result["audio_bytes"]).decode() if tts_result["success"] else None,
                "audio_base64": base64.b64encode(tts_result["audio_bytes"]).decode() if tts_result["success"] else None,
                "audio_format": tts_result.get("format", "mp3"),
                "error": stt_result["error"]
            })
        
        user_text = stt_result["text"]
        print(f"🎤 Transcribed: {user_text}")
        
        # 3. Get conversation history for context
        conversation_history = []
        conversation = None
        
        if conversation_id:
            conversation = db.query(Conversation).filter(Conversation.id == conversation_id).first()
            if conversation:
                messages = db.query(Message).filter(
                    Message.conversation_id == conversation_id
                ).order_by(Message.created_at.desc()).limit(10).all()
                
                conversation_history = [
                    {"role": msg.role, "content": msg.content}
                    for msg in reversed(messages)
                ]
        
        # Create new conversation if needed
        if not conversation:
            conversation = Conversation(title=user_text[:50] if len(user_text) > 50 else user_text)
            db.add(conversation)
            db.commit()
            db.refresh(conversation)
        
        # 4. Process with AI
        ai_result = gemini_service.chat(user_text, conversation_history)
        response_text = ai_result.get("response", "Îmi pare rău, nu am putut procesa cererea.")
        
        # 5. Handle search intent if detected
        intent = ai_result.get("intent")
        action_result = None
        
        print(f"🎯 Intent detected: {intent}")
        print(f"📦 Action data: {ai_result.get('action_data')}")
        print(f"❓ Needs confirmation: {ai_result.get('needs_confirmation')}")
        
        if intent == "search_internet" or ai_result.get("search_query"):
            search_query = ai_result.get("search_query") or ai_result.get("action_data", {}).get("query", user_text)
            print(f"🔍 Searching: {search_query}")
            
            search_results = search_service.search(search_query)
            if search_results["success"]:
                search_context = search_service.format_results_for_ai(search_results)
                # Re-process with search context
                ai_result = gemini_service.chat_with_search(user_text, search_context, conversation_history)
                response_text = ai_result.get("response", response_text)
                action_result = {"search_performed": True, "query": search_query}
        
        # 6. Execute other actions if detected (always execute for explicit commands)
        elif intent and intent not in ["general", "error"]:
            action_data = ai_result.get("action_data") or {}
            
            # Intents that don't require action_data (listing actions)
            list_intents = ["list_shopping", "list_tasks", "read_emails", "read_last_email"]
            
            # Execute action if we have data OR if it's a list intent
            if action_data or intent in list_intents:
                print(f"🚀 Executing action: {intent} with data: {action_data}")
                action_result = action_executor.execute(intent, action_data, db)
                print(f"✅ Action result: {action_result}")
                
                # Update response to confirm action was taken
                if action_result.get("success"):
                    if intent == "list_shopping":
                        # Format shopping list for voice
                        items = action_result.get("items", [])
                        if items:
                            items_text = ", ".join([f"{item['name']}" for item in items])
                            response_text = f"Pe lista ta de cumpărături ai: {items_text}."
                        else:
                            response_text = "Lista ta de cumpărături este goală."
                    elif intent == "list_tasks":
                        # Format tasks for voice
                        tasks = action_result.get("tasks", [])
                        if tasks:
                            tasks_text = ", ".join([task['title'] for task in tasks])
                            response_text = f"Ai următoarele task-uri: {tasks_text}."
                        else:
                            response_text = "Nu ai niciun task activ."
                    elif intent == "read_emails":
                        # Format email list for voice
                        emails = action_result.get("emails", [])
                        if emails:
                            emails_text = []
                            for e in emails[:5]:
                                emails_text.append(f"De la {e['from']}: {e['subject']}")
                            response_text = f"Ai {len(emails)} emailuri recente. " + ". ".join(emails_text) + "."
                        else:
                            response_text = "Nu ai emailuri noi în inbox."
                    elif intent == "read_last_email":
                        # Format last email for voice
                        email = action_result.get("email")
                        if email:
                            body_preview = email['body'][:500] if len(email['body']) > 500 else email['body']
                            response_text = f"Ultimul email este de la {email['from']}, cu subiectul: {email['subject']}. Conținutul: {body_preview}"
                        else:
                            response_text = "Nu ai emailuri noi în inbox."
                    elif intent == "search_emails":
                        # Format search results for voice
                        emails = action_result.get("emails", [])
                        if emails:
                            emails_text = []
                            for e in emails[:3]:
                                emails_text.append(f"De la {e['from']}: {e['subject']}")
                            response_text = f"Am găsit {len(emails)} emailuri. " + ". ".join(emails_text) + "."
                        else:
                            response_text = action_result.get("message", "Nu am găsit emailuri.")
                    elif intent == "summarize_email":
                        # Let AI summarize the email
                        email = action_result.get("email")
                        if email and action_result.get("needs_ai_summary"):
                            summary_prompt = f"Rezumă pe scurt următorul email de la {email['from']} cu subiectul '{email['subject']}':\n\n{email['body']}"
                            summary_result = gemini_service.chat(summary_prompt)
                            response_text = summary_result.get("response", f"Email de la {email['from']}: {email['subject']}")
                        else:
                            response_text = action_result.get("message", "Nu am putut rezuma emailul.")
                    elif action_result.get("message"):
                        response_text = action_result['message']
                elif not action_result.get("success") and action_result.get("error"):
                    response_text = f"Îmi pare rău, {action_result['error']}"
            else:
                print(f"⚠️ No action_data provided for intent: {intent}")
        
        print(f"🤖 Response: {response_text[:100]}...")
        
        # 7. Save messages to database
        user_message = Message(
            conversation_id=conversation.id,
            role="user",
            content=user_text
        )
        assistant_message = Message(
            conversation_id=conversation.id,
            role="assistant",
            content=response_text
        )
        db.add(user_message)
        db.add(assistant_message)
        
        # Update conversation
        conversation.updated_at = datetime.utcnow()
        db.commit()
        
        # 8. Text-to-Speech
        tts_result = tts_service.synthesize(response_text)
        audio_b64 = base64.b64encode(tts_result["audio_bytes"]).decode() if tts_result["success"] else None
        
        print(f"🔊 TTS generated: {len(tts_result.get('audio_bytes', b''))} bytes")
        
        return JSONResponse({
            "success": True,
            "conversation_id": conversation.id,
            "transcription": user_text,
            "user_text": user_text,
            "response": response_text,
            "response_text": response_text,
            "audio": audio_b64,
            "audio_base64": audio_b64,
            "audio_format": tts_result.get("format", "mp3"),
            "intent": intent,
            "action": action_result,
            "action_result": action_result,
            "needs_confirmation": ai_result.get("needs_confirmation", False),
            "follow_up": ai_result.get("follow_up_question")
        })
        
    except Exception as e:
        print(f"❌ Voice processing error: {e}")
        import traceback
        traceback.print_exc()
        
        error_message = "A apărut o eroare. Te rog încearcă din nou."
        tts_result = tts_service.synthesize(error_message)
        audio_b64 = base64.b64encode(tts_result["audio_bytes"]).decode() if tts_result["success"] else None
        
        return JSONResponse({
            "success": False,
            "error": str(e),
            "transcription": "",
            "response": error_message,
            "response_text": error_message,
            "audio": audio_b64,
            "audio_base64": audio_b64,
            "audio_format": "mp3"
        }, status_code=500)
        error_message = "A apărut o eroare. Te rog încearcă din nou."
        tts_result = tts_service.synthesize(error_message)
        
        return JSONResponse({
            "success": False,
            "error": str(e),
            "transcription": "",
            "response": error_message,
            "response_text": error_message,
            "audio": audio_b64,
            "audio_base64": audio_b64,
            "audio_format": "mp3"
        }, status_code=500)


@router.post("/text-to-speech")
async def text_to_speech(text: str = Form(...)):
    """
    Convert text to speech audio.
    Returns MP3 audio file.
    """
    try:
        result = tts_service.synthesize(text)
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result["error"])
        
        return Response(
            content=result["audio_bytes"],
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": "attachment; filename=response.mp3"
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/text-to-speech-base64")
async def text_to_speech_base64(text: str = Form(...)):
    """
    Convert text to speech audio.
    Returns base64 encoded audio.
    """
    try:
        result = tts_service.synthesize(text)
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result["error"])
        
        return JSONResponse({
            "success": True,
            "audio": base64.b64encode(result["audio_bytes"]).decode(),
            "audio_base64": base64.b64encode(result["audio_bytes"]).decode(),
            "format": result["format"]
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/speech-to-text")
async def speech_to_text(
    audio: UploadFile = File(...),
    audio_format: str = Form("wav")
):
    """
    Convert speech audio to text.
    """
    try:
        audio_bytes = await audio.read()
        result = stt_service.transcribe(audio_bytes, audio_format)
        
        return JSONResponse({
            "success": result["success"],
            "text": result["text"],
            "transcription": result["text"],
            "error": result.get("error")
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/chat")
async def chat_text(
    request: ChatRequest,
    db: Session = Depends(get_db)
):
    """
    Process text message (fallback when voice doesn't work).
    Returns text response with optional audio.
    """
    try:
        message = request.text
        conversation_id = request.conversation_id
        
        print(f"💬 Chat message: {message}")
        
        # Get conversation history
        conversation_history = []
        conversation = None
        
        if conversation_id:
            conversation = db.query(Conversation).filter(Conversation.id == conversation_id).first()
            if conversation:
                messages = db.query(Message).filter(
                    Message.conversation_id == conversation_id
                ).order_by(Message.created_at.desc()).limit(10).all()
                
                conversation_history = [
                    {"role": msg.role, "content": msg.content}
                    for msg in reversed(messages)
                ]
        
        # Create conversation if needed
        if not conversation:
            conversation = Conversation(title=message[:50])
            db.add(conversation)
            db.commit()
            db.refresh(conversation)
        
        # Process with AI
        ai_result = gemini_service.chat(message, conversation_history)
        response_text = ai_result.get("response", "Îmi pare rău, nu am putut procesa cererea.")
        
        # Handle search intent
        intent = ai_result.get("intent")
        action_result = None
        
        if intent == "search_internet" or ai_result.get("search_query"):
            search_query = ai_result.get("search_query") or ai_result.get("action_data", {}).get("query", message)
            print(f"🔍 Searching: {search_query}")
            
            search_results = search_service.search(search_query)
            if search_results["success"]:
                search_context = search_service.format_results_for_ai(search_results)
                ai_result = gemini_service.chat_with_search(message, search_context, conversation_history)
                response_text = ai_result.get("response", response_text)
                action_result = {"search_performed": True, "query": search_query}
        
        # Execute other actions if needed
        elif intent and intent not in ["general", "error"]:
            action_data = ai_result.get("action_data") or {}
            
            # Intents that don't require action_data (listing actions)
            list_intents = ["list_shopping", "list_tasks", "read_emails", "read_last_email"]
            
            # Execute action if we have data OR if it's a list intent
            if action_data or intent in list_intents:
                print(f"🚀 Executing action: {intent} with data: {action_data}")
                action_result = action_executor.execute(intent, action_data, db)
                print(f"✅ Action result: {action_result}")
                
                # Update response based on action result
                if action_result.get("success"):
                    if intent == "list_shopping":
                        items = action_result.get("items", [])
                        if items:
                            items_text = ", ".join([f"{item['name']}" for item in items])
                            response_text = f"Pe lista ta de cumpărături ai: {items_text}."
                        else:
                            response_text = "Lista ta de cumpărături este goală."
                    elif intent == "list_tasks":
                        tasks = action_result.get("tasks", [])
                        if tasks:
                            tasks_text = ", ".join([task['title'] for task in tasks])
                            response_text = f"Ai următoarele task-uri: {tasks_text}."
                        else:
                            response_text = "Nu ai niciun task activ."
                    elif intent == "read_emails":
                        # Format email list for text
                        emails = action_result.get("emails", [])
                        if emails:
                            emails_text = []
                            for e in emails[:5]:
                                emails_text.append(f"De la {e['from']}: {e['subject']}")
                            response_text = f"Ai {len(emails)} emailuri recente. " + ". ".join(emails_text) + "."
                        else:
                            response_text = "Nu ai emailuri noi în inbox."
                    elif intent == "read_last_email":
                        # Format last email for text
                        email = action_result.get("email")
                        if email:
                            body_preview = email['body'][:500] if len(email['body']) > 500 else email['body']
                            response_text = f"Ultimul email este de la {email['from']}, cu subiectul: {email['subject']}. Conținutul: {body_preview}"
                        else:
                            response_text = "Nu ai emailuri noi în inbox."
                    elif intent == "search_emails":
                        # Format search results for text
                        emails = action_result.get("emails", [])
                        if emails:
                            emails_text = []
                            for e in emails[:3]:
                                emails_text.append(f"De la {e['from']}: {e['subject']}")
                            response_text = f"Am găsit {len(emails)} emailuri. " + ". ".join(emails_text) + "."
                        else:
                            response_text = action_result.get("message", "Nu am găsit emailuri.")
                    elif intent == "summarize_email":
                        # Let AI summarize the email
                        email = action_result.get("email")
                        if email and action_result.get("needs_ai_summary"):
                            summary_prompt = f"Rezumă pe scurt următorul email de la {email['from']} cu subiectul '{email['subject']}':\n\n{email['body']}"
                            summary_result = gemini_service.chat(summary_prompt)
                            response_text = summary_result.get("response", f"Email de la {email['from']}: {email['subject']}")
                        else:
                            response_text = action_result.get("message", "Nu am putut rezuma emailul.")
                    elif action_result.get("message"):
                        response_text = action_result['message']
                elif not action_result.get("success") and action_result.get("error"):
                    response_text = f"Îmi pare rău, {action_result['error']}"
        
        # Save messages
        db.add(Message(conversation_id=conversation.id, role="user", content=message))
        db.add(Message(conversation_id=conversation.id, role="assistant", content=response_text))
        db.commit()
        
        # Generate audio
        tts_result = tts_service.synthesize(response_text)
        audio_b64 = base64.b64encode(tts_result["audio_bytes"]).decode() if tts_result["success"] else None
        
        print(f"🤖 Response: {response_text[:100]}...")
        
        return JSONResponse({
            "success": True,
            "conversation_id": conversation.id,
            "response": response_text,
            "response_text": response_text,
            "audio": audio_b64,
            "audio_base64": audio_b64,
            "audio_format": "mp3",
            "intent": intent,
            "action": action_result,
            "action_result": action_result
        })
        
    except Exception as e:
        print(f"❌ Chat error: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

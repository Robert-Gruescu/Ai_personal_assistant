"""
Google Gemini AI Service
Handles AI conversation and intent detection with internet search capability
"""
import json
import asyncio
import google.generativeai as genai
from typing import Optional, List, Dict, Any
from datetime import datetime
from app.config import GEMINI_API_KEY

# Configure Gemini
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
    print(f"🔑 Gemini API configured with key: {GEMINI_API_KEY[:10]}...")
else:
    print("⚠️ WARNING: GEMINI_API_KEY not configured!")


class GeminiService:
    """Handles interaction with Google Gemini AI"""
    
    # Available models in order of preference
    AVAILABLE_MODELS = [
        'models/gemini-2.5-flash',           # Best balance of speed and capability
        'models/gemini-2.0-flash',           # Fast and capable
        'models/gemini-2.0-flash-lite',      # Lighter version
        'models/gemini-2.5-pro',             # Most capable but slower
    ]
    
    def __init__(self):
        if not GEMINI_API_KEY:
            print("⚠️ Gemini API key not set. AI features will not work.")
            self.model = None
            self.model_name = None
            return
        
        self.model = None
        self.model_name = None
        
        # Use first available model without testing (to save API quota)
        model_name = self.AVAILABLE_MODELS[0]
        print(f"🔄 Using model: {model_name}")
        self.model = genai.GenerativeModel(
            model_name,
            generation_config=genai.GenerationConfig(
                temperature=0.7,
                top_p=0.9,
                top_k=40,
                max_output_tokens=2048,
            )
        )
        self.model_name = model_name
        print(f"✅ Gemini model '{model_name}' configured (no startup test to save quota)")
        
        self.system_prompt = self._build_system_prompt()
        
    def _build_system_prompt(self) -> str:
        """Build the system prompt for the AI assistant"""
        current_date = datetime.now().strftime("%d %B %Y")
        current_time = datetime.now().strftime("%H:%M")
        
        return f"""Ești ASIS, un asistent personal AI vocal în limba română. Data curentă: {current_date}, ora: {current_time}.

PERSONALITATE:
- Ești prietenos, empatic și util
- Răspunzi natural, ca într-o conversație reală cu un prieten
- Folosești un ton cald dar profesional
- Răspunsurile sunt concise (1-3 propoziții pentru întrebări simple)
- Pentru explicații complexe, poți fi mai detaliat
- Vorbești ca un om, nu ca un robot

CAPABILITĂȚI:
1. TASK-URI: Poți adăuga, lista, marca complete sau șterge task-uri
2. CUMPĂRĂTURI: Gestionezi liste de cumpărături și sugerezi reduceri
3. INFORMAȚII: Poți căuta informații pe internet când e necesar
4. EMAIL TRIMITERE: Poți trimite emailuri când utilizatorul cere explicit
5. EMAIL CITIRE: Poți citi și rezuma emailuri din inbox-ul utilizatorului
6. REMINDER-URI: Poți seta reminder-uri pentru task-uri
7. CĂUTARE: Poți căuta pe internet informații actuale
8. CALENDAR: Poți adăuga evenimente în Google Calendar
9. ÎNTÂLNIRI: Poți programa întâlniri cu Google Meet, trimite invitații și reminder-uri prin email

REGULI PENTRU PROGRAMARE ÎNTÂLNIRI:
- Când utilizatorul vrea să programeze o întâlnire/meeting, extrage: titlu, dată, oră, email invitat, nume invitat
- Creezi automat un link Google Meet
- Trimiți email de invitație persoanei respective
- Programezi reminder prin email cu 1 oră înainte pentru ambele persoane
- Adaugi evenimentul în calendarul utilizatorului

REGULI IMPORTANTE PENTRU ACȚIUNI:
- Când utilizatorul CERE EXPLICIT să adaugi ceva (ex: "adaugă lapte pe listă", "pune pâine pe lista de cumpărături", "salvează task"), EXECUTĂ IMEDIAT acțiunea
- Setează "needs_confirmation": false când comanda e clară și explicită
- Setează "needs_confirmation": true DOAR când utilizatorul doar menționează ceva vag fără a cere explicit
- După executare, confirmă ce ai făcut (ex: "Am adăugat laptele pe lista de cumpărături!")
- Pune întrebări de follow-up naturale ("Mai ai nevoie de altceva?")
- Când ai nevoie de informații actuale (vreme, știri, prețuri), caută pe internet

EXEMPLE ACȚIUNE IMEDIATĂ (needs_confirmation: false):
- "adaugă lapte pe lista de cumpărături" -> EXECUTĂ, confirmă
- "pune 2 kg mere pe listă" -> EXECUTĂ, confirmă
- "salvează task: să sun la doctor" -> EXECUTĂ, confirmă
- "șterge laptele de pe listă" -> EXECUTĂ, confirmă
- "programează o întâlnire cu Ion mâine la 14:00" -> EXECUTĂ, confirmă
- "fă un meet cu ana@email.com poimâine la 10" -> EXECUTĂ, confirmă

EXEMPLE CU CONFIRMARE (needs_confirmation: true):
- "am nevoie de lapte" (menționare, nu comandă) -> întreabă dacă vrea să adaugi
- "trebuie să sun la doctor" (menționare, nu comandă) -> întreabă dacă vrea să salvezi task
- "ar trebui să vorbesc cu Ion" (vag) -> întreabă detalii

RĂSPUNS FORMAT:
Răspunde DOAR cu un JSON valid în formatul:
{{
    "response": "răspunsul tău vocal către utilizator - trebuie să sune natural când e citit cu voce tare",
    "intent": "tipul de acțiune detectată sau null",
    "action_data": {{date relevante pentru acțiune}} sau null,
    "needs_confirmation": false pentru comenzi explicite / true pentru mențiuni vagi,
    "follow_up_question": "întrebare de follow-up" sau null,
    "search_query": "termeni de căutare pe internet dacă e nevoie" sau null
}}

INTENT-URI POSIBILE:
- "add_task": adaugă task-uri (action_data: {{title: "...", description: "...", due_date: null, priority: "medium"}} SAU pentru multiple: [{{title: "..."}} , {{title: "..."}}])
- "list_tasks": listează task-uri
- "complete_task": marchează task complet (action_data: {{task_id: N}} sau {{task_title: "..."}})
- "add_shopping_item": adaugă la cumpărături (action_data: {{name: "...", quantity: "...", category: "..."}} SAU pentru multiple: [{{name: "lapte"}}, {{name: "pâine"}}, {{name: "ouă"}}])
- "list_shopping": listează cumpărături
- "remove_shopping_item": șterge de pe listă (action_data: {{item_id: N}} sau {{item_name: "..."}})
- "send_email": trimite email (action_data: {{to: "...", subject: "...", body: "..."}})
- "read_emails": citește emailurile recente din inbox (action_data: {{count: 5}}) - implicit 5 emailuri
- "read_last_email": citește ultimul email primit (action_data: null)
- "search_emails": caută emailuri după subiect sau expeditor (action_data: {{query: "..."}})
- "summarize_email": rezumă un email specific (action_data: {{index: N}} - N=1 pentru ultimul)
- "search_internet": caută informații (action_data: {{query: "..."}})
- "schedule_meeting": programează întâlnire cu Meet (action_data: {{title: "...", date: "YYYY-MM-DD", time: "HH:MM", attendee_email: "...", attendee_name: "...", description: "...", duration_minutes: 60, reminder_hours: 1}})
- "add_calendar_event": adaugă eveniment simplu în calendar (action_data: {{title: "...", date: "YYYY-MM-DD", time: "HH:MM", description: "...", duration_minutes: 60}})
- "list_calendar_events": listează evenimentele din calendar
- "cancel_calendar_event": anulează eveniment (action_data: {{title: "..."}} sau {{event_id: N}})

REGULI PENTRU MULTIPLE PRODUSE/TASK-URI:
- Când utilizatorul cere să adaugi MAI MULTE produse sau task-uri deodată, folosește action_data ca ARRAY
- Exemplu: "adaugă lapte, pâine și ouă" -> action_data: [{{name: "lapte"}}, {{name: "pâine"}}, {{name: "ouă"}}]
- Exemplu: "am 3 task-uri: X, Y, Z" -> action_data: [{{title: "X"}}, {{title: "Y"}}, {{title: "Z"}}]
- "general": conversație generală (fără acțiune specială)

REGULI PENTRU CITIRE EMAIL:
- "citește-mi emailurile" sau "ce emailuri am" -> read_emails cu count: 5
- "citește ultimul email" sau "ce mi-a scris X" -> read_last_email
- "caută emailuri de la Ion" sau "emailuri despre proiect" -> search_emails
- "fă-mi rezumat la ultimul email" sau "rezumă emailul" -> summarize_email cu index: 1
- "rezumă emailul de la X" -> mai întâi search_emails pentru a găsi emailul

IMPORTANT: 
- Răspunsul trebuie să fie natural și fluid pentru a fi citit cu voce tare!
- Pentru comenzi explicite de adăugare/ștergere, ÎNTOTDEAUNA setează needs_confirmation: false și include action_data complet!
- Pentru întâlniri, extrage data în format YYYY-MM-DD și ora în format HH:MM
- Dacă utilizatorul spune "mâine", "poimâine", calculează data corectă bazată pe data curentă: {current_date}
"""

    def chat(self, user_message: str, conversation_history: Optional[List[Dict]] = None) -> Dict[str, Any]:
        """
        Process user message and generate AI response
        
        Args:
            user_message: The user's message
            conversation_history: Previous messages for context
            
        Returns:
            Dict with response, intent, action_data, etc.
        """
        if not self.model:
            return {
                "response": "Îmi pare rău, serviciul AI nu este configurat. Verifică cheia API Gemini.",
                "intent": "error",
                "action_data": None,
                "needs_confirmation": False,
                "follow_up_question": None,
                "error": "Gemini API key not configured"
            }
            
        try:
            # Build conversation context
            messages = []
            
            if conversation_history:
                for msg in conversation_history[-10:]:  # Last 10 messages for context
                    role = "user" if msg.get("role") == "user" else "model"
                    messages.append({
                        "role": role,
                        "parts": [msg.get("content", "")]
                    })
            
            # Add current message with system prompt
            full_prompt = f"{self.system_prompt}\n\nMesajul utilizatorului: {user_message}"
            
            # Generate response
            if messages:
                chat = self.model.start_chat(history=messages)
                response = chat.send_message(full_prompt)
            else:
                response = self.model.generate_content(full_prompt)
            
            # Parse response
            response_text = response.text.strip()
            
            # Try to parse as JSON
            return self._parse_response(response_text)
                
        except Exception as e:
            error_msg = str(e)
            print(f"Gemini error: {error_msg}")
            
            # Provide user-friendly error messages
            if "quota" in error_msg.lower():
                user_error = "Am atins limita de cereri. Te rog încearcă din nou mai târziu."
            elif "invalid" in error_msg.lower() and "key" in error_msg.lower():
                user_error = "Cheia API nu este validă. Verifică configurația."
            elif "network" in error_msg.lower() or "connection" in error_msg.lower():
                user_error = "Probleme de conexiune la internet. Verifică rețeaua."
            else:
                user_error = "Îmi pare rău, am întâmpinat o problemă. Poți repeta?"
            
            return {
                "response": user_error,
                "intent": "error",
                "action_data": None,
                "needs_confirmation": False,
                "follow_up_question": None,
                "error": error_msg
            }
    
    def _parse_response(self, response_text: str) -> Dict[str, Any]:
        """Parse the AI response and extract JSON"""
        try:
            # Clean up response if needed
            cleaned = response_text.strip()
            
            # Remove markdown code blocks
            if cleaned.startswith("```json"):
                cleaned = cleaned[7:]
            elif cleaned.startswith("```"):
                cleaned = cleaned[3:]
            if cleaned.endswith("```"):
                cleaned = cleaned[:-3]
            
            cleaned = cleaned.strip()
            
            result = json.loads(cleaned)
            
            # Validate required fields
            if "response" not in result:
                result["response"] = "Am înțeles cererea ta."
            if "intent" not in result:
                result["intent"] = "general"
            if "action_data" not in result:
                result["action_data"] = None
            if "needs_confirmation" not in result:
                result["needs_confirmation"] = False
            if "follow_up_question" not in result:
                result["follow_up_question"] = None
                
            return result
            
        except json.JSONDecodeError:
            # If not valid JSON, try to extract response field manually
            import re
            match = re.search(r'"response"\s*:\s*"((?:[^"\\]|\\.)*)"', response_text)
            if match:
                extracted_response = match.group(1).replace('\\"', '"').replace('\\n', ' ')
            else:
                # Remove JSON artifacts and return clean text
                extracted_response = response_text
                for pattern in ['```json', '```', '{', '}', '"response":', '"intent":', '"action_data":']:
                    extracted_response = extracted_response.replace(pattern, '')
                extracted_response = extracted_response.strip()
                if not extracted_response or len(extracted_response) < 5:
                    extracted_response = "Am înțeles cererea ta."
            
            # Try to extract intent from raw text
            intent = "general"
            intent_match = re.search(r'"intent"\s*:\s*"([^"]+)"', response_text)
            if intent_match:
                intent = intent_match.group(1)
            
            # Try to extract action_data
            action_data = None
            if intent in ["add_shopping_item", "add_task"]:
                name_match = re.search(r'"name"\s*:\s*"([^"]+)"', response_text)
                if name_match:
                    action_data = {"name": name_match.group(1)}
                title_match = re.search(r'"title"\s*:\s*"([^"]+)"', response_text)
                if title_match:
                    action_data = {"title": title_match.group(1)}
            
            return {
                "response": extracted_response,
                "intent": intent,
                "action_data": action_data,
                "needs_confirmation": False,
                "follow_up_question": None
            }
    
    def chat_with_search(self, user_message: str, search_results: str, conversation_history: Optional[List[Dict]] = None) -> Dict[str, Any]:
        """Process user message with search results as context"""
        enhanced_prompt = f"""
Informații găsite pe internet:
{search_results}

Folosește aceste informații pentru a răspunde la întrebarea utilizatorului.
Întrebarea utilizatorului: {user_message}
"""
        return self.chat(enhanced_prompt, conversation_history)
    
    def generate_summary(self, items: List[str], context: str = "items") -> str:
        """Generate a natural language summary of items"""
        if not self.model:
            return f"Ai {len(items)} {context}."
            
        try:
            prompt = f"Generează un rezumat scurt și natural în română pentru aceste {context}: {', '.join(items)}. Răspunde cu o propoziție scurtă și naturală."
            response = self.model.generate_content(prompt)
            return response.text.strip()
        except Exception as e:
            print(f"Summary generation error: {e}")
            return f"Ai {len(items)} {context}."


# Singleton instance
gemini_service = GeminiService()

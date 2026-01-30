"""
Text-to-Speech Service
Converts text to natural-sounding speech using Edge-TTS (Microsoft Neural Voices)
with gTTS fallback when Edge-TTS is unavailable
"""
import io
import asyncio
import hashlib
from pathlib import Path
from typing import Dict, Any

try:
    import edge_tts
    EDGE_TTS_AVAILABLE = True
except ImportError:
    EDGE_TTS_AVAILABLE = False
    print("⚠️ edge-tts not available")

try:
    from gtts import gTTS
    GTTS_AVAILABLE = True
except ImportError:
    GTTS_AVAILABLE = False
    print("⚠️ gTTS not available")

from pydub import AudioSegment
from app.config import AUDIO_DIR, SPEECH_LANGUAGE


class TextToSpeechService:
    """Handles conversion of text to speech audio"""
    
    # Romanian voices for Edge-TTS
    VOICES = {
        "ro": {
            "male": "ro-RO-EmilNeural",
            "female": "ro-RO-AlinaNeural",
        },
        "en": {
            "male": "en-US-GuyNeural",
            "female": "en-US-JennyNeural",
        }
    }
    
    def __init__(self):
        lang_code = SPEECH_LANGUAGE.split("-")[0]  # 'ro' from 'ro-RO'
        self.language = lang_code
        self.voice = self.VOICES.get(lang_code, self.VOICES["ro"])["female"]
        self.cache_dir = AUDIO_DIR / "tts_cache"
        self.cache_dir.mkdir(exist_ok=True)
        self.edge_tts_working = EDGE_TTS_AVAILABLE
        print(f"✅ TTS initialized with voice: {self.voice}")
        print(f"   Edge-TTS: {'available' if EDGE_TTS_AVAILABLE else 'not available'}")
        print(f"   gTTS: {'available' if GTTS_AVAILABLE else 'not available'}")
    
    def _get_cache_path(self, text: str, engine: str = "edge") -> Path:
        """Generate cache file path based on text hash"""
        text_hash = hashlib.md5(f"{text}_{self.voice}_{engine}".encode()).hexdigest()
        return self.cache_dir / f"{text_hash}.mp3"
    
    def _synthesize_gtts(self, text: str, slow: bool = False) -> Dict[str, Any]:
        """Fallback synthesis using gTTS"""
        try:
            if not GTTS_AVAILABLE:
                return {
                    "success": False,
                    "audio_bytes": None,
                    "format": None,
                    "error": "gTTS not available"
                }
            
            cache_path = self._get_cache_path(text, "gtts")
            if cache_path.exists():
                with open(cache_path, "rb") as f:
                    return {
                        "success": True,
                        "audio_bytes": f.read(),
                        "format": "mp3",
                        "error": None
                    }
            
            tts = gTTS(text=text, lang=self.language, slow=slow)
            audio_buffer = io.BytesIO()
            tts.write_to_fp(audio_buffer)
            audio_buffer.seek(0)
            audio_bytes = audio_buffer.read()
            
            # Cache for future use
            with open(cache_path, "wb") as f:
                f.write(audio_bytes)
            
            return {
                "success": True,
                "audio_bytes": audio_bytes,
                "format": "mp3",
                "error": None
            }
        except Exception as e:
            print(f"gTTS error: {e}")
            return {
                "success": False,
                "audio_bytes": None,
                "format": None,
                "error": f"gTTS error: {str(e)}"
            }
    
    async def _synthesize_edge_async(self, text: str, slow: bool = False) -> Dict[str, Any]:
        """Async synthesis using Edge-TTS"""
        try:
            if not EDGE_TTS_AVAILABLE or not self.edge_tts_working:
                raise Exception("Edge-TTS not available")
            
            if not text or not text.strip():
                return {
                    "success": False,
                    "audio_bytes": None,
                    "format": None,
                    "error": "Empty text provided"
                }
            
            # Check cache first
            cache_path = self._get_cache_path(text, "edge")
            if cache_path.exists():
                with open(cache_path, "rb") as f:
                    audio_bytes = f.read()
                return {
                    "success": True,
                    "audio_bytes": audio_bytes,
                    "format": "mp3",
                    "error": None
                }
            
            # Configure rate
            rate = "-10%" if slow else "+5%"
            
            # Generate speech using Edge-TTS
            communicate = edge_tts.Communicate(
                text=text,
                voice=self.voice,
                rate=rate
            )
            
            # Collect audio chunks
            audio_data = b""
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    audio_data += chunk["data"]
            
            if not audio_data:
                raise Exception("No audio generated")
            
            # Cache for future use
            with open(cache_path, "wb") as f:
                f.write(audio_data)
            
            return {
                "success": True,
                "audio_bytes": audio_data,
                "format": "mp3",
                "error": None
            }
            
        except Exception as e:
            print(f"Edge-TTS error: {e}")
            # Mark Edge-TTS as not working and try fallback
            self.edge_tts_working = False
            return {
                "success": False,
                "audio_bytes": None,
                "format": None,
                "error": f"Edge-TTS error: {str(e)}"
            }
    
    async def _synthesize_async(self, text: str, slow: bool = False) -> Dict[str, Any]:
        """Async synthesis with fallback"""
        if not text or not text.strip():
            return {
                "success": False,
                "audio_bytes": None,
                "format": None,
                "error": "Empty text provided"
            }
        
        # Try Edge-TTS first
        if self.edge_tts_working:
            result = await self._synthesize_edge_async(text, slow)
            if result["success"]:
                return result
        
        # Fallback to gTTS
        print("⚠️ Falling back to gTTS")
        return self._synthesize_gtts(text, slow)
    
    def synthesize(self, text: str, slow: bool = False) -> Dict[str, Any]:
        """
        Convert text to speech audio (synchronous wrapper)
        
        Args:
            text: Text to convert to speech
            slow: Whether to speak slowly
            
        Returns:
            dict with 'success', 'audio_bytes', 'format', and 'error' keys
        """
        if not text or not text.strip():
            return {
                "success": False,
                "audio_bytes": None,
                "format": None,
                "error": "Empty text provided"
            }
        
        try:
            # Try async Edge-TTS first
            if self.edge_tts_working:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                try:
                    result = loop.run_until_complete(self._synthesize_edge_async(text, slow))
                    if result["success"]:
                        return result
                finally:
                    loop.close()
            
            # Fallback to gTTS
            print("⚠️ Falling back to gTTS")
            return self._synthesize_gtts(text, slow)
            
        except Exception as e:
            print(f"Synthesize error: {e}")
            # Last resort: try gTTS
            return self._synthesize_gtts(text, slow)
    
    async def synthesize_async(self, text: str, slow: bool = False) -> Dict[str, Any]:
        """Async version for use in async contexts"""
        return await self._synthesize_async(text, slow)
    
    def synthesize_to_wav(self, text: str) -> Dict[str, Any]:
        """Convert text to WAV format audio"""
        result = self.synthesize(text)
        
        if not result["success"]:
            return result
        
        try:
            # Convert MP3 to WAV
            audio = AudioSegment.from_mp3(io.BytesIO(result["audio_bytes"]))
            wav_buffer = io.BytesIO()
            audio.export(wav_buffer, format="wav")
            wav_buffer.seek(0)
            
            return {
                "success": True,
                "audio_bytes": wav_buffer.read(),
                "format": "wav",
                "error": None
            }
        except Exception as e:
            return {
                "success": False,
                "audio_bytes": None,
                "format": None,
                "error": f"WAV conversion error: {str(e)}"
            }
    
    def set_voice(self, gender: str = "female"):
        """Set voice gender (male/female)"""
        voices = self.VOICES.get(self.language, self.VOICES["ro"])
        self.voice = voices.get(gender, voices["female"])
        print(f"Voice changed to: {self.voice}")
    
    async def get_available_voices(self) -> list:
        """Get list of available voices"""
        if not EDGE_TTS_AVAILABLE:
            return []
        try:
            voices = await edge_tts.list_voices()
            return [v for v in voices if v["Locale"].startswith(self.language)]
        except Exception as e:
            print(f"Error listing voices: {e}")
            return []


# Singleton instance
tts_service = TextToSpeechService()

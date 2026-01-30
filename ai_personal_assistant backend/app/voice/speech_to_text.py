"""
Speech-to-Text Service
Converts audio input to text using Google Speech Recognition
"""
import io
import speech_recognition as sr
from pydub import AudioSegment
from app.config import SPEECH_LANGUAGE


class SpeechToTextService:
    """Handles conversion of audio to text"""
    
    def __init__(self):
        self.recognizer = sr.Recognizer()
        self.language = SPEECH_LANGUAGE
    
    def convert_audio_to_wav(self, audio_bytes: bytes, input_format: str = "webm") -> bytes:
        """Convert audio from any format to WAV for processing"""
        try:
            audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format=input_format)
            # Convert to mono, 16kHz for better recognition
            audio = audio.set_channels(1).set_frame_rate(16000)
            
            wav_buffer = io.BytesIO()
            audio.export(wav_buffer, format="wav")
            wav_buffer.seek(0)
            return wav_buffer.read()
        except Exception as e:
            print(f"Audio conversion error: {e}")
            # Try without specifying format
            audio = AudioSegment.from_file(io.BytesIO(audio_bytes))
            audio = audio.set_channels(1).set_frame_rate(16000)
            wav_buffer = io.BytesIO()
            audio.export(wav_buffer, format="wav")
            wav_buffer.seek(0)
            return wav_buffer.read()
    
    def transcribe(self, audio_bytes: bytes, input_format: str = "webm") -> dict:
        """
        Transcribe audio to text
        
        Args:
            audio_bytes: Raw audio data
            input_format: Audio format (webm, wav, mp3, ogg, etc.)
            
        Returns:
            dict with 'success', 'text', and 'error' keys
        """
        try:
            print(f"🎙️ STT: Starting transcription, input_format={input_format}, bytes={len(audio_bytes)}")
            
            # Convert to WAV if not already
            if input_format != "wav":
                wav_bytes = self.convert_audio_to_wav(audio_bytes, input_format)
            else:
                # For WAV, just use as is - Flutter already sends proper format
                wav_bytes = audio_bytes
                print(f"🎙️ STT: Using original WAV, {len(wav_bytes)} bytes")
            
            # Use speech recognition
            with sr.AudioFile(io.BytesIO(wav_bytes)) as source:
                audio_data = self.recognizer.record(source)
                duration = len(audio_data.get_raw_data()) / (16000 * 2)  # 16kHz, 16-bit
                print(f"🎙️ STT: Audio duration ~{duration:.2f}s, {len(audio_data.get_raw_data())} raw bytes")
            
            # Check if audio is too short
            if duration < 0.5:
                print("🎙️ STT: ⚠️ Audio too short for recognition")
                return {
                    "success": False,
                    "text": "",
                    "error": "Înregistrarea e prea scurtă. Ține apăsat mai mult timp."
                }
            
            # Try Google Speech Recognition (free)
            try:
                print(f"🎙️ STT: Calling Google Speech Recognition, language={self.language}")
                text = self.recognizer.recognize_google(
                    audio_data, 
                    language=self.language
                )
                print(f"🎙️ STT: ✅ Transcription success: '{text}'")
                return {
                    "success": True,
                    "text": text,
                    "error": None
                }
            except sr.UnknownValueError:
                print("🎙️ STT: ❌ Could not understand audio (UnknownValueError)")
                return {
                    "success": False,
                    "text": "",
                    "error": "Nu am înțeles. Vorbește mai clar sau mai aproape de microfon."
                }
            except sr.RequestError as e:
                print(f"🎙️ STT: ❌ Service error: {e}")
                return {
                    "success": False,
                    "text": "",
                    "error": f"Speech recognition service error: {e}"
                }
                
        except Exception as e:
            print(f"🎙️ STT: ❌ Exception: {e}")
            return {
                "success": False,
                "text": "",
                "error": f"Transcription error: {str(e)}"
            }


# Singleton instance
stt_service = SpeechToTextService()

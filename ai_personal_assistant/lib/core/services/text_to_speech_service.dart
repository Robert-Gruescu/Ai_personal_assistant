import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io';

/// Text-to-Speech Service using Flutter TTS plugin
class TextToSpeechService {
  static final TextToSpeechService _instance = TextToSpeechService._internal();
  factory TextToSpeechService() => _instance;
  TextToSpeechService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String _language = 'ro-RO';
  double _volume = 1.0;
  double _pitch = 1.0;
  double _rate = 0.5;

  // Callbacks
  Function()? onStart;
  Function()? onComplete;
  Function(String error)? onError;

  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;

  /// Initialize the TTS engine
  Future<bool> initialize({
    String language = 'ro-RO',
    double volume = 1.0,
    double pitch = 1.0,
    double rate = 0.5,
  }) async {
    _language = language;
    _volume = volume;
    _pitch = pitch;
    _rate = rate;

    try {
      // Set up handlers
      _tts.setStartHandler(() {
        _isSpeaking = true;
        onStart?.call();
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        onComplete?.call();
      });

      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        print('❌ TTS Error: $msg');
        onError?.call(msg);
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
      });

      _tts.setPauseHandler(() {
        _isSpeaking = false;
      });

      _tts.setContinueHandler(() {
        _isSpeaking = true;
      });

      // Configure TTS
      await _tts.setLanguage(_language);
      await _tts.setVolume(_volume);
      await _tts.setPitch(_pitch);
      await _tts.setSpeechRate(_rate);

      // Platform-specific settings
      if (Platform.isAndroid) {
        await _tts.setQueueMode(1); // Queue mode

        // Try to set Romanian voice
        final voices = await _tts.getVoices;
        if (voices != null) {
          for (final voice in voices) {
            if (voice['locale']?.toString().startsWith('ro') == true) {
              await _tts.setVoice({
                'name': voice['name'],
                'locale': voice['locale'],
              });
              print('✅ Selected Romanian voice: ${voice['name']}');
              break;
            }
          }
        }
      }

      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
      }

      _isInitialized = true;
      print('✅ Text-to-Speech initialized with language: $_language');
      return true;
    } catch (e) {
      print('❌ TTS initialization error: $e');
      return false;
    }
  }

  /// Speak the given text
  Future<bool> speak(String text) async {
    if (!_isInitialized) {
      await initialize(language: _language);
    }

    if (text.isEmpty) return false;

    try {
      // Stop any current speech
      if (_isSpeaking) {
        await stop();
      }

      // Clean up text for better speech
      final cleanText = _cleanTextForSpeech(text);

      print('🔊 Speaking: $cleanText');
      await _tts.speak(cleanText);
      return true;
    } catch (e) {
      print('❌ TTS speak error: $e');
      return false;
    }
  }

  /// Clean text for better speech synthesis
  String _cleanTextForSpeech(String text) {
    return text
        // Remove markdown formatting
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'\1')
        .replaceAll(RegExp(r'`([^`]+)`'), r'\1')
        // Remove URLs
        .replaceAll(RegExp(r'https?://[^\s]+'), 'link')
        // Remove emojis (keep some basic ones)
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F5FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '')
        // Normalize whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Stop speaking
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Pause speaking
  Future<void> pause() async {
    await _tts.pause();
    _isSpeaking = false;
  }

  /// Set the speech rate (0.0 to 1.0)
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.0, 1.0);
    await _tts.setSpeechRate(_rate);
  }

  /// Set the volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _tts.setVolume(_volume);
  }

  /// Set the pitch (0.5 to 2.0)
  Future<void> setPitch(double pitch) async {
    _pitch = pitch.clamp(0.5, 2.0);
    await _tts.setPitch(_pitch);
  }

  /// Set the language
  Future<bool> setLanguage(String language) async {
    _language = language;
    try {
      await _tts.setLanguage(language);
      return true;
    } catch (e) {
      print('⚠️ Failed to set language: $e');
      return false;
    }
  }

  /// Get available languages
  Future<List<dynamic>> getLanguages() async {
    return await _tts.getLanguages ?? [];
  }

  /// Get available voices
  Future<List<dynamic>> getVoices() async {
    return await _tts.getVoices ?? [];
  }

  /// Check if a language is available
  Future<bool> isLanguageAvailable(String language) async {
    final result = await _tts.isLanguageAvailable(language);
    return result == 1;
  }

  /// Dispose resources
  void dispose() {
    _tts.stop();
    _isInitialized = false;
    _isSpeaking = false;
  }
}

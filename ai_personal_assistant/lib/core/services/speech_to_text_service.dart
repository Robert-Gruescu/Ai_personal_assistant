import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// Speech-to-Text result
class STTResult {
  final bool success;
  final String text;
  final String? error;
  final double? confidence;

  STTResult({
    required this.success,
    required this.text,
    this.error,
    this.confidence,
  });

  factory STTResult.success(String text, {double? confidence}) =>
      STTResult(success: true, text: text, confidence: confidence);

  factory STTResult.error(String errorMessage) =>
      STTResult(success: false, text: '', error: errorMessage);
}

/// Speech-to-Text Service using Flutter's speech_to_text plugin
class SpeechToTextService {
  static final SpeechToTextService _instance = SpeechToTextService._internal();
  factory SpeechToTextService() => _instance;
  SpeechToTextService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String _language = 'ro-RO';

  String _lastResult = '';
  double _lastConfidence = 0.0;
  String? _lastError;

  // Callbacks
  Function(String text)? onResult;
  Function(String error)? onError;
  Function()? onListeningStarted;
  Function()? onListeningStopped;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  String get lastResult => _lastResult;

  /// Initialize the speech recognition
  Future<bool> initialize({String language = 'ro-RO'}) async {
    _language = language;

    try {
      _isInitialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: false,
      );

      if (_isInitialized) {
        print('✅ Speech-to-Text initialized');

        // Check if Romanian is available
        final locales = await _speech.locales();
        final hasRomanian = locales.any((l) => l.localeId.startsWith('ro'));
        if (!hasRomanian) {
          print('⚠️ Romanian language not available, using default');
        }
      } else {
        print('⚠️ Speech-to-Text initialization failed');
      }

      return _isInitialized;
    } catch (e) {
      print('❌ Speech-to-Text initialization error: $e');
      return false;
    }
  }

  void _onStatus(String status) {
    print('🎤 STT Status: $status');
    if (status == 'listening') {
      _isListening = true;
      onListeningStarted?.call();
    } else if (status == 'notListening' || status == 'done') {
      _isListening = false;
      onListeningStopped?.call();
    }
  }

  void _onError(SpeechRecognitionError error) {
    print('❌ STT Error: ${error.errorMsg}');
    _lastError = error.errorMsg;
    _isListening = false;
    onError?.call(error.errorMsg);
    onListeningStopped?.call();
  }

  /// Start listening for speech
  Future<bool> startListening() async {
    if (!_isInitialized) {
      final initialized = await initialize(language: _language);
      if (!initialized) return false;
    }

    if (_isListening) {
      await stopListening();
    }

    _lastResult = '';
    _lastConfidence = 0.0;
    _lastError = null;

    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: _language,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      );

      _isListening = true;
      return true;
    } catch (e) {
      print('❌ Error starting speech recognition: $e');
      _lastError = e.toString();
      return false;
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    _lastResult = result.recognizedWords;
    _lastConfidence = result.confidence;

    print(
      '🎤 Recognized: $_lastResult (confidence: $_lastConfidence, final: ${result.finalResult})',
    );

    if (result.finalResult) {
      onResult?.call(_lastResult);
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }

  /// Cancel listening
  Future<void> cancelListening() async {
    await _speech.cancel();
    _isListening = false;
    _lastResult = '';
  }

  /// Get the current result
  STTResult getResult() {
    if (_lastError != null) {
      return STTResult.error(_lastError!);
    }
    if (_lastResult.isEmpty) {
      return STTResult.error('Nu am înțeles ce ai spus. Poți repeta?');
    }
    return STTResult.success(_lastResult, confidence: _lastConfidence);
  }

  /// Get available languages
  Future<List<LocaleName>> getAvailableLanguages() async {
    if (!_isInitialized) {
      await initialize();
    }
    return await _speech.locales();
  }

  /// Check if speech recognition is available
  Future<bool> isAvailable() async {
    return await _speech.initialize();
  }

  /// Dispose resources
  void dispose() {
    _speech.cancel();
    _isListening = false;
    _isInitialized = false;
  }
}

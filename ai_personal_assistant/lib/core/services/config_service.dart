import 'package:shared_preferences/shared_preferences.dart';

/// Configuration service for app settings
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  SharedPreferences? _prefs;
  bool _isInitialized = false;

  // Config keys
  static const String _keyGeminiApiKey = 'gemini_api_key';
  static const String _keySmtpHost = 'smtp_host';
  static const String _keySmtpPort = 'smtp_port';
  static const String _keySmtpUser = 'smtp_user';
  static const String _keySmtpPassword = 'smtp_password';
  static const String _keyImapHost = 'imap_host';
  static const String _keyImapPort = 'imap_port';
  static const String _keySpeechLanguage = 'speech_language';
  static const String _keyTheme = 'theme';
  static const String _keyTtsRate = 'tts_rate';
  static const String _keyTtsVolume = 'tts_volume';

  // Default values
  static const String defaultSmtpHost = 'smtp.gmail.com';
  static const int defaultSmtpPort = 587;
  static const String defaultImapHost = 'imap.gmail.com';
  static const int defaultImapPort = 993;
  static const String defaultSpeechLanguage = 'ro-RO';
  static const String defaultTheme = 'light';
  static const double defaultTtsRate = 0.5;
  static const double defaultTtsVolume = 1.0;

  /// Initialize the config service
  Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
    print('✅ Config service initialized');
  }

  /// Ensure initialization
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // ============ GEMINI API ============

  Future<String?> get geminiApiKey async {
    await _ensureInitialized();
    return _prefs?.getString(_keyGeminiApiKey);
  }

  Future<void> setGeminiApiKey(String apiKey) async {
    await _ensureInitialized();
    await _prefs?.setString(_keyGeminiApiKey, apiKey);
  }

  // ============ SMTP SETTINGS ============

  Future<String> get smtpHost async {
    await _ensureInitialized();
    return _prefs?.getString(_keySmtpHost) ?? defaultSmtpHost;
  }

  Future<void> setSmtpHost(String host) async {
    await _ensureInitialized();
    await _prefs?.setString(_keySmtpHost, host);
  }

  Future<int> get smtpPort async {
    await _ensureInitialized();
    return _prefs?.getInt(_keySmtpPort) ?? defaultSmtpPort;
  }

  Future<void> setSmtpPort(int port) async {
    await _ensureInitialized();
    await _prefs?.setInt(_keySmtpPort, port);
  }

  Future<String?> get smtpUser async {
    await _ensureInitialized();
    return _prefs?.getString(_keySmtpUser);
  }

  Future<void> setSmtpUser(String user) async {
    await _ensureInitialized();
    await _prefs?.setString(_keySmtpUser, user);
  }

  Future<String?> get smtpPassword async {
    await _ensureInitialized();
    return _prefs?.getString(_keySmtpPassword);
  }

  Future<void> setSmtpPassword(String password) async {
    await _ensureInitialized();
    await _prefs?.setString(_keySmtpPassword, password);
  }

  // ============ IMAP SETTINGS ============

  Future<String> get imapHost async {
    await _ensureInitialized();
    return _prefs?.getString(_keyImapHost) ?? defaultImapHost;
  }

  Future<void> setImapHost(String host) async {
    await _ensureInitialized();
    await _prefs?.setString(_keyImapHost, host);
  }

  Future<int> get imapPort async {
    await _ensureInitialized();
    return _prefs?.getInt(_keyImapPort) ?? defaultImapPort;
  }

  Future<void> setImapPort(int port) async {
    await _ensureInitialized();
    await _prefs?.setInt(_keyImapPort, port);
  }

  // ============ SPEECH SETTINGS ============

  Future<String> get speechLanguage async {
    await _ensureInitialized();
    return _prefs?.getString(_keySpeechLanguage) ?? defaultSpeechLanguage;
  }

  Future<void> setSpeechLanguage(String language) async {
    await _ensureInitialized();
    await _prefs?.setString(_keySpeechLanguage, language);
  }

  // ============ THEME SETTINGS ============

  Future<String> get theme async {
    await _ensureInitialized();
    return _prefs?.getString(_keyTheme) ?? defaultTheme;
  }

  Future<void> setTheme(String theme) async {
    await _ensureInitialized();
    await _prefs?.setString(_keyTheme, theme);
  }

  Future<bool> get isDarkMode async {
    return (await theme) == 'dark';
  }

  // ============ TTS SETTINGS ============

  Future<double> get ttsRate async {
    await _ensureInitialized();
    return _prefs?.getDouble(_keyTtsRate) ?? defaultTtsRate;
  }

  Future<void> setTtsRate(double rate) async {
    await _ensureInitialized();
    await _prefs?.setDouble(_keyTtsRate, rate);
  }

  Future<double> get ttsVolume async {
    await _ensureInitialized();
    return _prefs?.getDouble(_keyTtsVolume) ?? defaultTtsVolume;
  }

  Future<void> setTtsVolume(double volume) async {
    await _ensureInitialized();
    await _prefs?.setDouble(_keyTtsVolume, volume);
  }

  // ============ EMAIL CONFIG HELPER ============

  Future<Map<String, dynamic>> getEmailConfig() async {
    return {
      'smtp_host': await smtpHost,
      'smtp_port': await smtpPort,
      'smtp_user': await smtpUser,
      'smtp_password': await smtpPassword,
      'imap_host': await imapHost,
      'imap_port': await imapPort,
    };
  }

  Future<void> setEmailConfig({
    required String smtpUser,
    required String smtpPassword,
    String? smtpHost,
    int? smtpPort,
    String? imapHost,
    int? imapPort,
  }) async {
    await setSmtpUser(smtpUser);
    await setSmtpPassword(smtpPassword);
    if (smtpHost != null) await setSmtpHost(smtpHost);
    if (smtpPort != null) await setSmtpPort(smtpPort);
    if (imapHost != null) await setImapHost(imapHost);
    if (imapPort != null) await setImapPort(imapPort);
  }

  // ============ UTILITY ============

  Future<void> clearAll() async {
    await _ensureInitialized();
    await _prefs?.clear();
  }

  Future<bool> get isConfigured async {
    final apiKey = await geminiApiKey;
    return apiKey != null && apiKey.isNotEmpty;
  }
}

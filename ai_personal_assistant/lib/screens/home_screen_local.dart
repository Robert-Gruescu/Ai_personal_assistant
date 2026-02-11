import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../services/local_assistant_service.dart';
import '../core/services/services.dart';

// Clase pentru sesiuni și mesaje
class Session {
  String id;
  String title;
  List<Message> messages;

  Session({required this.id, required this.title, List<Message>? messages})
    : messages = messages ?? [];
}

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  Message({required this.text, required this.isUser, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // --- State ---
  bool isRecording = false;
  bool isProcessing = false;
  bool isPlaying = false;
  bool isServiceReady = false;
  bool isApiKeyConfigured = false;

  String statusText = "Inițializare...";

  String sessionId = "";
  List<Session> sessions = [];

  bool showSettings = false;
  String theme = "light";
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Local Service (totul local, fără server)
  final LocalAssistantService _service = LocalAssistantService();
  final SpeechToTextService _stt = SpeechToTextService();
  final TextToSpeechService _tts = TextToSpeechService();
  final ConfigService _config = ConfigService();

  // Animație orb
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Creăm sesiune inițială
    _createInitialSession();

    // Inițializăm serviciile
    _initializeServices();
  }

  void _createInitialSession() {
    var newSession = Session(id: _generateUUID(), title: "Conversație Nouă");
    newSession.messages.add(
      Message(
        text:
            "Salut! Sunt ASIS, asistentul tău personal vocal. Totul rulează local pe telefon! Cum te pot ajuta?",
        isUser: false,
      ),
    );
    sessions.add(newSession);
    sessionId = newSession.id;
  }

  Future<void> _initializeServices() async {
    setState(() {
      statusText = "🔄 Inițializez serviciile...";
    });

    try {
      // Initialize local service
      await _service.initialize();

      // Check if API key is configured
      final apiKey = await _config.geminiApiKey;
      isApiKeyConfigured = apiKey != null && apiKey.isNotEmpty;

      // Setup TTS callbacks
      _tts.onStart = () {
        if (mounted) setState(() => isPlaying = true);
      };
      _tts.onComplete = () {
        if (mounted) setState(() => isPlaying = false);
      };

      // Setup STT callbacks
      _stt.onResult = (text) {
        if (text.isNotEmpty) {
          _processVoiceResult(text);
        }
      };
      _stt.onError = (error) {
        if (mounted) {
          setState(() {
            isRecording = false;
            statusText = "⚠️ Eroare microfon: $error";
          });
        }
      };
      _stt.onListeningStarted = () {
        if (mounted) {
          setState(() {
            isRecording = true;
            statusText = "🎤 Te ascult... Apasă din nou pentru a trimite";
          });
        }
      };
      _stt.onListeningStopped = () {
        if (mounted && isRecording) {
          setState(() {
            isRecording = false;
          });
        }
      };

      setState(() {
        isServiceReady = true;
        if (isApiKeyConfigured) {
          statusText = "🎤 Apasă pe microfon pentru a vorbi";
        } else {
          statusText = "⚠️ Configurează cheia API Gemini în setări";
        }
      });
    } catch (e) {
      setState(() {
        statusText = "⚠️ Eroare la inițializare: $e";
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    _stt.dispose();
    _tts.dispose();
    super.dispose();
  }

  String _generateUUID() {
    var rand = Random();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  Session get _currentSession {
    return sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => sessions.first,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Funcții sesiuni ---
  void _createNewSession() {
    var newId = _generateUUID();
    var newSession = Session(id: newId, title: "Conversație Nouă");
    newSession.messages.add(
      Message(text: "Sesiune nouă! Cum te pot ajuta?", isUser: false),
    );
    setState(() {
      sessions.insert(0, newSession);
      sessionId = newId;
      statusText = "Sesiune nouă creată.";
    });
    _service.clearHistory();
  }

  void _switchSession(String id) {
    setState(() {
      sessionId = id;
      statusText = "Am schimbat conversația.";
    });
    _service.clearHistory();
  }

  void _deleteSession(String id) {
    setState(() {
      sessions.removeWhere((s) => s.id == id);
      if (sessionId == id && sessions.isNotEmpty) {
        sessionId = sessions.first.id;
      } else if (sessions.isEmpty) {
        _createInitialSession();
      }
    });
  }

  // --- Voice Input folosind STT local ---
  Future<void> _toggleRecording() async {
    if (isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!isApiKeyConfigured) {
      _showApiKeyDialog();
      return;
    }

    try {
      final started = await _stt.startListening();
      if (!started) {
        setState(() {
          statusText = "⚠️ Nu am putut porni microfonul";
        });
      }
    } catch (e) {
      setState(() {
        statusText = "⚠️ Eroare: $e";
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      final text = await _service.stopListening();
      setState(() {
        isRecording = false;
      });

      if (text != null && text.isNotEmpty) {
        _processVoiceResult(text);
      } else {
        setState(() {
          statusText = "🎤 Nu am înțeles. Încearcă din nou.";
        });
      }
    } catch (e) {
      setState(() {
        isRecording = false;
        statusText = "⚠️ Eroare: $e";
      });
    }
  }

  Future<void> _processVoiceResult(String text) async {
    setState(() {
      isRecording = false;
      isProcessing = true;
      statusText = "🔄 Procesez...";

      // Adaugă mesajul utilizatorului
      _currentSession.messages.add(Message(text: text, isUser: true));

      // Actualizează titlul
      if (_currentSession.title == "Conversație Nouă" && text.length > 3) {
        _currentSession.title = text.length > 30
            ? '${text.substring(0, 30)}...'
            : text;
      }
    });

    _scrollToBottom();

    try {
      final result = await _service.sendMessage(text);

      setState(() {
        isProcessing = false;
        _currentSession.messages.add(
          Message(text: result.response, isUser: false),
        );
        statusText = "🎤 Apasă pe microfon pentru a continua";
      });

      _scrollToBottom();

      // Citește răspunsul cu voce
      await _tts.speak(result.response);
    } catch (e) {
      setState(() {
        isProcessing = false;
        statusText = "⚠️ Eroare: $e";
        _currentSession.messages.add(
          Message(text: "Îmi pare rău, am întâmpinat o eroare.", isUser: false),
        );
      });
    }
  }

  // --- Trimitere text ---
  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (!isApiKeyConfigured) {
      _showApiKeyDialog();
      return;
    }

    _textController.clear();

    setState(() {
      isProcessing = true;
      statusText = "🔄 Procesez...";
      _currentSession.messages.add(Message(text: text, isUser: true));

      // Actualizează titlul
      if (_currentSession.title == "Conversație Nouă" && text.length > 3) {
        _currentSession.title = text.length > 30
            ? '${text.substring(0, 30)}...'
            : text;
      }
    });

    _scrollToBottom();

    try {
      final result = await _service.sendMessage(text);

      setState(() {
        isProcessing = false;
        _currentSession.messages.add(
          Message(text: result.response, isUser: false),
        );
        statusText = "✅ Scrie un mesaj sau apasă pe microfon";
      });

      _scrollToBottom();

      // Citește răspunsul cu voce
      await _tts.speak(result.response);
    } catch (e) {
      setState(() {
        isProcessing = false;
        statusText = "⚠️ Eroare: $e";
      });
    }
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurare API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pentru a folosi asistentul, trebuie să configurezi cheia API Google Gemini.\n\n'
              'Poți obține o cheie gratuită de la:\n'
              'https://aistudio.google.com/apikey',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key Gemini',
                hintText: 'AIza...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () async {
              final apiKey = _apiKeyController.text.trim();
              if (apiKey.isNotEmpty) {
                await _config.setGeminiApiKey(apiKey);
                final success = await _service.configureApiKey(apiKey);

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {
                    isApiKeyConfigured = success;
                    statusText = success
                        ? "✅ API Key configurat! Apasă pe microfon pentru a vorbi."
                        : "⚠️ API Key invalid";
                  });
                }
              }
            },
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Setări'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('Cheie API Gemini'),
              subtitle: Text(
                isApiKeyConfigured ? 'Configurată' : 'Neconfigurată',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _showApiKeyDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Configurare Email'),
              subtitle: const Text('SMTP settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _showEmailConfigDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Șterge toate datele'),
              subtitle: const Text('Conversații, task-uri, etc.'),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirmare'),
                    content: const Text(
                      'Ești sigur că vrei să ștergi toate datele?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Anulează'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Șterge'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await DatabaseService().clearAllData();
                  if (mounted) {
                    setState(() {
                      sessions.clear();
                      _createInitialSession();
                    });
                  }
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Închide'),
          ),
        ],
      ),
    );
  }

  void _showEmailConfigDialog() async {
    // Încarcă valorile salvate anterior
    final savedEmail = await _config.smtpUser;
    final savedPassword = await _config.smtpPassword;

    print('📧 DEBUG: Loaded email: $savedEmail');
    print(
      '📧 DEBUG: Password exists: ${savedPassword != null && savedPassword.isNotEmpty}',
    );

    final smtpUserController = TextEditingController(text: savedEmail ?? '');
    final smtpPasswordController = TextEditingController(
      text: savedPassword ?? '',
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurare Email'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status actual
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (savedEmail != null && savedEmail.isNotEmpty)
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      (savedEmail != null && savedEmail.isNotEmpty)
                          ? Icons.check_circle
                          : Icons.warning,
                      color: (savedEmail != null && savedEmail.isNotEmpty)
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (savedEmail != null && savedEmail.isNotEmpty)
                            ? 'Configurat: $savedEmail'
                            : 'Email neconfigurat',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pentru a trimite emailuri, configurează contul Gmail.\n'
                'Folosește o parolă de aplicație dacă ai 2FA activat.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: smtpUserController,
                decoration: const InputDecoration(
                  labelText: 'Email (Gmail)',
                  hintText: 'exemplu@gmail.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: smtpPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Parolă / App Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = smtpUserController.text.trim();
              final password = smtpPasswordController.text;

              if (email.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completează email și parola!')),
                );
                return;
              }

              print('📧 DEBUG: Saving email: $email');
              print('📧 DEBUG: Password length: ${password.length}');

              await _config.setEmailConfig(
                smtpUser: email,
                smtpPassword: password,
              );

              // Verifică că s-a salvat
              final checkEmail = await _config.smtpUser;
              final checkPass = await _config.smtpPassword;
              print('📧 DEBUG: Verified saved email: $checkEmail');
              print(
                '📧 DEBUG: Verified password exists: ${checkPass != null && checkPass.isNotEmpty}',
              );

              // Reîncarcă configurația email-ului pentru a aplica noile credențiale
              await _service.reloadEmailConfig();

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Email configurat: $email')),
                );
              }
            },
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
  }

  Color _getOrbColor() {
    if (isProcessing) return Colors.orange;
    if (isRecording) return Colors.red;
    if (isPlaying) return Colors.green;
    if (!isApiKeyConfigured) return Colors.grey;
    return Colors.indigo;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = theme == "dark";
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.indigo.shade50,
      body: SafeArea(
        child: Row(
          children: [
            // --- SIDEBAR ---
            if (isWideScreen)
              Container(
                width: 280,
                color: isDark ? Colors.grey.shade800 : Colors.white,
                padding: const EdgeInsets.all(16),
                child: _buildSidebar(isDark),
              ),

            // --- ZONA PRINCIPALĂ ---
            Expanded(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (!isWideScreen)
                          IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () =>
                                _showSidebarDrawer(context, isDark),
                          ),
                        const Text(
                          "ASIS",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isApiKeyConfigured
                                ? Colors.green
                                : Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isApiKeyConfigured ? "Local" : "Config",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.settings),
                          onPressed: _showSettingsDialog,
                          tooltip: "Setări",
                        ),
                      ],
                    ),
                  ),

                  // Chat messages
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _buildChatArea(isDark),
                    ),
                  ),

                  // Status și control
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Status text
                        Text(
                          statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Input area
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Text input
                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                  maxHeight: 120,
                                ),
                                child: TextField(
                                  controller: _textController,
                                  maxLines: null,
                                  minLines: 1,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText: "Scrie un mesaj...",
                                    filled: true,
                                    fillColor: isDark
                                        ? Colors.grey.shade800
                                        : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  enabled: !isProcessing,
                                  onSubmitted: (_) => _sendTextMessage(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Send button
                            IconButton(
                              onPressed: !isProcessing
                                  ? _sendTextMessage
                                  : null,
                              icon: const Icon(Icons.send),
                              color: Colors.indigo,
                            ),
                            const SizedBox(width: 8),

                            // Mic button - VOICE INPUT
                            GestureDetector(
                              onTap: !isProcessing ? _toggleRecording : null,
                              child: AnimatedBuilder(
                                animation: _controller,
                                builder: (context, child) {
                                  double scale = 1.0;
                                  if (isRecording) {
                                    scale =
                                        1.0 +
                                        0.1 * sin(_controller.value * 2 * pi);
                                  }
                                  return Transform.scale(
                                    scale: scale,
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _getOrbColor(),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _getOrbColor().withOpacity(
                                              0.5,
                                            ),
                                            blurRadius: isRecording ? 20 : 10,
                                            spreadRadius: isRecording ? 5 : 2,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        isRecording
                                            ? Icons.stop
                                            : (isProcessing
                                                  ? Icons.hourglass_empty
                                                  : (isPlaying
                                                        ? Icons.volume_up
                                                        : Icons.mic)),
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isRecording
                              ? "Apasă din nou pentru a trimite"
                              : "Apasă pe microfon pentru a vorbi",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Column(
      children: [
        const CircleAvatar(
          radius: 32,
          backgroundColor: Colors.indigo,
          child: Icon(Icons.smart_toy, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 12),
        const Text(
          "ASIS",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const Text(
          "Asistent Personal Local",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            "📱 Rulează pe telefon",
            style: TextStyle(fontSize: 10, color: Colors.green),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _createNewSession,
          icon: const Icon(Icons.add),
          label: const Text("Conversație Nouă"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Conversații",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              var s = sessions[index];
              bool selected = s.id == sessionId;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: Colors.indigo.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: const Icon(Icons.chat_bubble_outline, size: 20),
                  title: Text(
                    s.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteSession(s.id),
                  ),
                  onTap: () => _switchSession(s.id),
                ),
              );
            },
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: const Text("Temă"),
          trailing: Switch(
            value: theme == "dark",
            onChanged: (value) {
              setState(() {
                theme = value ? "dark" : "light";
              });
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text("Setări"),
          onTap: _showSettingsDialog,
        ),
      ],
    );
  }

  Widget _buildChatArea(bool isDark) {
    final messages = _currentSession.messages;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: Column(
              crossAxisAlignment: msg.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? Colors.indigo
                        : (isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade200),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                      bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                    ),
                  ),
                  child: SelectableText(
                    msg.text,
                    style: TextStyle(
                      color: msg.isUser
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ),
                // Butoane pentru mesajele AI
                if (!msg.isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: msg.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Text copiat!'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.copy,
                                size: 14,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Copiază',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () => _tts.speak(msg.text),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.volume_up,
                                size: 14,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Ascultă',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSidebarDrawer(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: _buildSidebar(isDark),
          );
        },
      ),
    );
  }
}

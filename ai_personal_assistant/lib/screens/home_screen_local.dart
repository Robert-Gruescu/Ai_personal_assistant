import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../services/local_assistant_service.dart';
import '../core/services/services.dart';
import '../core/models/models.dart';

// ─── Model classes ────────────────────────────────────────────────────────────

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

// ─── HomeScreen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  bool isRecording = false;
  bool isProcessing = false;
  bool isPlaying = false;
  bool isServiceReady = false;
  bool isApiKeyConfigured = false;

  String statusText = 'Inițializare...';
  String sessionId = '';
  List<Session> sessions = [];

  String theme = 'light';

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── Services ───────────────────────────────────────────────────────────────
  final LocalAssistantService _service = LocalAssistantService();
  final SpeechToTextService _stt = SpeechToTextService();
  final TextToSpeechService _tts = TextToSpeechService();
  final ConfigService _config = ConfigService();

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _controller;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _createInitialSession();
    _initializeServices();
  }

  void _createInitialSession() {
    final s = Session(id: _generateUUID(), title: 'Conversație Nouă');
    s.messages.add(
      Message(
        text:
            'Salut! Sunt ASIS, asistentul tău personal vocal. Totul rulează local pe telefon! Cum te pot ajuta?',
        isUser: false,
      ),
    );
    sessions.add(s);
    sessionId = s.id;
  }

  Future<void> _initializeServices() async {
    setState(() => statusText = '🔄 Inițializez serviciile...');

    try {
      await _service.initialize();

      final apiKey = await _config.geminiApiKey;
      isApiKeyConfigured = apiKey != null && apiKey.isNotEmpty;

      _tts.onStart = () {
        if (mounted) setState(() => isPlaying = true);
      };
      _tts.onComplete = () {
        if (mounted) setState(() => isPlaying = false);
      };

      _stt.onResult = (text) {
        if (text.isNotEmpty) _processVoiceResult(text);
      };
      _stt.onError = (error) {
        if (mounted)
          setState(() {
            isRecording = false;
            statusText = '⚠️ Eroare microfon: $error';
          });
      };
      _stt.onListeningStarted = () {
        if (mounted)
          setState(() {
            isRecording = true;
            statusText = '🎤 Te ascult... Apasă din nou pentru a trimite';
          });
      };
      _stt.onListeningStopped = () {
        if (mounted && isRecording) setState(() => isRecording = false);
      };

      setState(() {
        isServiceReady = true;
        statusText = isApiKeyConfigured
            ? '🎤 Apasă pe microfon pentru a vorbi'
            : '⚠️ Configurează cheia API Gemini în setări';
      });
    } catch (e) {
      setState(() => statusText = '⚠️ Eroare la inițializare: $e');
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

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _generateUUID() {
    final rand = Random();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  Session get _currentSession => sessions.firstWhere(
    (s) => s.id == sessionId,
    orElse: () => sessions.first,
  );

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

  Color _getOrbColor() {
    if (isProcessing) return Colors.orange;
    if (isRecording) return Colors.red;
    if (isPlaying) return Colors.green;
    if (!isApiKeyConfigured) return Colors.grey;
    return Colors.indigo;
  }

  // ── Session management ─────────────────────────────────────────────────────
  void _createNewSession() {
    final newId = _generateUUID();
    final s = Session(id: newId, title: 'Conversație Nouă');
    s.messages.add(
      Message(text: 'Sesiune nouă! Cum te pot ajuta?', isUser: false),
    );
    setState(() {
      sessions.insert(0, s);
      sessionId = newId;
      statusText = 'Sesiune nouă creată.';
    });
    _service.clearHistory();
  }

  void _switchSession(String id) {
    setState(() {
      sessionId = id;
      statusText = 'Am schimbat conversația.';
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

  // ── Voice ──────────────────────────────────────────────────────────────────
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
      if (!started)
        setState(() => statusText = '⚠️ Nu am putut porni microfonul');
    } catch (e) {
      setState(() => statusText = '⚠️ Eroare: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final text = await _service.stopListening();
      setState(() => isRecording = false);
      if (text != null && text.isNotEmpty) {
        _processVoiceResult(text);
      } else {
        setState(() => statusText = '🎤 Nu am înțeles. Încearcă din nou.');
      }
    } catch (e) {
      setState(() {
        isRecording = false;
        statusText = '⚠️ Eroare: $e';
      });
    }
  }

  Future<void> _processVoiceResult(String text) async {
    setState(() {
      isRecording = false;
      isProcessing = true;
      statusText = '🔄 Procesez...';
      _currentSession.messages.add(Message(text: text, isUser: true));
      if (_currentSession.title == 'Conversație Nouă' && text.length > 3) {
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
        statusText = '🎤 Apasă pe microfon pentru a continua';
      });
      _scrollToBottom();
      await _tts.speak(result.response);
    } catch (e) {
      setState(() {
        isProcessing = false;
        statusText = '⚠️ Eroare: $e';
        _currentSession.messages.add(
          Message(text: 'Îmi pare rău, am întâmpinat o eroare.', isUser: false),
        );
      });
    }
  }

  // ── Text send ──────────────────────────────────────────────────────────────
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
      statusText = '🔄 Procesez...';
      _currentSession.messages.add(Message(text: text, isUser: true));
      if (_currentSession.title == 'Conversație Nouă' && text.length > 3) {
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
        statusText = '✅ Scrie un mesaj sau apasă pe microfon';
      });
      _scrollToBottom();
      await _tts.speak(result.response);
    } catch (e) {
      setState(() {
        isProcessing = false;
        statusText = '⚠️ Eroare: $e';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM SHEETS — Tasks & Shopping
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens the Tasks bottom sheet and loads tasks from the database.
  void _showTasksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TasksSheet(db: DatabaseService()),
    );
  }

  /// Opens the Shopping bottom sheet and loads items from the database.
  void _showShoppingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShoppingSheet(db: DatabaseService()),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ─────────────────────────────────────────────────────────────────────────

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
              'Poți obține o cheie gratuită de la:\nhttps://aistudio.google.com/apikey',
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
                        ? '✅ API Key configurat! Apasă pe microfon pentru a vorbi.'
                        : '⚠️ API Key invalid';
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
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirmare'),
                    content: const Text(
                      'Ești sigur că vrei să ștergi toate datele?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Anulează'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
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
                  if (mounted)
                    setState(() {
                      sessions.clear();
                      _createInitialSession();
                    });
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
    final savedEmail = await _config.smtpUser;
    final savedPassword = await _config.smtpPassword;
    final smtpUserCtrl = TextEditingController(text: savedEmail ?? '');
    final smtpPasswordCtrl = TextEditingController(text: savedPassword ?? '');
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurare Email'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                controller: smtpUserCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email (Gmail)',
                  hintText: 'exemplu@gmail.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: smtpPasswordCtrl,
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
              final email = smtpUserCtrl.text.trim();
              final password = smtpPasswordCtrl.text;
              if (email.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completează email și parola!')),
                );
                return;
              }
              await _config.setEmailConfig(
                smtpUser: email,
                smtpPassword: password,
              );
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

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isDark = theme == 'dark';

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.indigo.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Hamburger → drawer
                  IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => _showSidebarDrawer(context, isDark),
                  ),
                  const Text(
                    'ASIS',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isApiKeyConfigured ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isApiKeyConfigured ? 'Local' : 'Config',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  // Quick-access buttons in header
                  IconButton(
                    icon: const Icon(Icons.checklist_rounded),
                    tooltip: 'Task-uri',
                    color: Colors.indigo,
                    onPressed: _showTasksSheet,
                  ),
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    tooltip: 'Cumpărături',
                    color: Colors.indigo,
                    onPressed: _showShoppingSheet,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: _showSettingsDialog,
                    tooltip: 'Setări',
                  ),
                ],
              ),
            ),

            // ── Chat area ────────────────────────────────────────────────────
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

            // ── Status + controls ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                              hintText: 'Scrie un mesaj...',
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
                      // Send
                      IconButton(
                        onPressed: !isProcessing ? _sendTextMessage : null,
                        icon: const Icon(Icons.send),
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 8),
                      // Mic orb
                      GestureDetector(
                        onTap: !isProcessing ? _toggleRecording : null,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            double scale = 1.0;
                            if (isRecording) {
                              scale =
                                  1.0 + 0.1 * sin(_controller.value * 2 * pi);
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
                                      color: _getOrbColor().withOpacity(0.5),
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
                        ? 'Apasă din nou pentru a trimite'
                        : 'Apasă pe microfon pentru a vorbi',
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sidebar drawer (mobile)
  // ─────────────────────────────────────────────────────────────────────────

  void _showSidebarDrawer(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: _buildSidebar(isDark),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sidebar content
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSidebar(bool isDark) {
    return Column(
      children: [
        // Profile area
        const CircleAvatar(
          radius: 32,
          backgroundColor: Colors.indigo,
          child: Icon(Icons.smart_toy, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 12),
        const Text(
          'ASIS',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const Text(
          'Asistent Personal Local',
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
            '📱 Rulează pe telefon',
            style: TextStyle(fontSize: 10, color: Colors.green),
          ),
        ),
        const SizedBox(height: 20),

        // ── Task & Shopping quick-access buttons ─────────────────────────
        Row(
          children: [
            Expanded(
              child: _SidebarActionButton(
                icon: Icons.checklist_rounded,
                label: 'Task-uri',
                color: Colors.indigo,
                onTap: () {
                  Navigator.pop(context); // close drawer first
                  _showTasksSheet();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SidebarActionButton(
                icon: Icons.shopping_cart_outlined,
                label: 'Cumpărături',
                color: Colors.teal,
                onTap: () {
                  Navigator.pop(context);
                  _showShoppingSheet();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // New conversation button
        ElevatedButton.icon(
          onPressed: _createNewSession,
          icon: const Icon(Icons.add),
          label: const Text('Conversație Nouă'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
        const SizedBox(height: 16),

        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Conversații',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),

        // Conversation list
        Expanded(
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (_, index) {
              final s = sessions[index];
              final selected = s.id == sessionId;
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
          title: const Text('Temă'),
          trailing: Switch(
            value: theme == 'dark',
            onChanged: (v) => setState(() => theme = v ? 'dark' : 'light'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Setări'),
          onTap: _showSettingsDialog,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Chat area
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatArea(bool isDark) {
    final messages = _currentSession.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (_, index) {
        final msg = messages[index];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar Action Button widget
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SidebarActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tasks Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TasksSheet extends StatefulWidget {
  final DatabaseService db;
  const _TasksSheet({required this.db});

  @override
  State<_TasksSheet> createState() => _TasksSheetState();
}

class _TasksSheetState extends State<_TasksSheet> {
  List<Task> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await widget.db.getAllTasks(completed: false);
    if (mounted)
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
  }

  Future<void> _complete(Task task) async {
    await widget.db.completeTask(task.id);
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ "${task.title}" marcat ca finalizat')),
      );
    }
  }

  Future<void> _delete(Task task) async {
    await widget.db.deleteTask(task.id);
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Row(
            children: [
              const Icon(
                Icons.checklist_rounded,
                color: Colors.indigo,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Task-uri active',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_tasks.length} task${_tasks.length != 1 ? "-uri" : ""}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // List
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.task_alt, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Nu ai task-uri active!',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _tasks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final task = _tasks[i];
                  final priorityColor = task.priority == 3
                      ? Colors.red
                      : task.priority == 2
                      ? Colors.orange
                      : Colors.green;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    leading: GestureDetector(
                      onTap: () => _complete(task),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.indigo, width: 2),
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                    title: Text(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: task.dueDate != null
                        ? Text(
                            '📅 ${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                            style: const TextStyle(fontSize: 12),
                          )
                        : task.category != null
                        ? Text(
                            task.category!,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Priority dot
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: priorityColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Delete
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          onPressed: () => _delete(task),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shopping Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ShoppingSheet extends StatefulWidget {
  final DatabaseService db;
  const _ShoppingSheet({required this.db});

  @override
  State<_ShoppingSheet> createState() => _ShoppingSheetState();
}

class _ShoppingSheetState extends State<_ShoppingSheet> {
  List<ShoppingItem> _items = [];
  bool _loading = true;
  bool _showPurchased = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getAllShoppingItems(
      purchased: _showPurchased ? null : false,
    );
    if (mounted)
      setState(() {
        _items = items;
        _loading = false;
      });
  }

  Future<void> _markPurchased(ShoppingItem item) async {
    await widget.db.markShoppingItemPurchased(item.id);
    setState(() {
      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx != -1) {
        _items[idx] = item.copyWith(isPurchased: true);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🛒 "${item.name}" marcat ca cumpărat')),
      );
    }
  }

  Future<void> _delete(ShoppingItem item) async {
    await widget.db.deleteShoppingItem(item.id);
    setState(() => _items.removeWhere((i) => i.id == item.id));
  }

  @override
  Widget build(BuildContext context) {
    final unpurchased = _items.where((i) => !i.isPurchased).toList();
    final purchased = _items.where((i) => i.isPurchased).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Row(
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.teal,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Lista de cumpărături',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Toggle show purchased
              TextButton(
                onPressed: () {
                  setState(() {
                    _showPurchased = !_showPurchased;
                    _loading = true;
                  });
                  _load();
                },
                child: Text(
                  _showPurchased ? 'Ascunde cumpărate' : 'Arată toate',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),

          // Remaining count
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${unpurchased.length} de cumpărat',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Lista de cumpărături este goală!',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  // ── Items to buy ────────────────────────────────────────
                  ...unpurchased.map(
                    (item) => _ShoppingTile(
                      item: item,
                      onCheck: () => _markPurchased(item),
                      onDelete: () => _delete(item),
                    ),
                  ),

                  // ── Already purchased ───────────────────────────────────
                  if (_showPurchased && purchased.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '✅ Deja cumpărate',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...purchased.map(
                      (item) => _ShoppingTile(
                        item: item,
                        purchased: true,
                        onCheck: null,
                        onDelete: () => _delete(item),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Single shopping tile ──────────────────────────────────────────────────────

class _ShoppingTile extends StatelessWidget {
  final ShoppingItem item;
  final bool purchased;
  final VoidCallback? onCheck;
  final VoidCallback onDelete;

  const _ShoppingTile({
    required this.item,
    this.purchased = false,
    required this.onCheck,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: GestureDetector(
        onTap: onCheck,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: purchased ? Colors.teal : Colors.transparent,
            border: Border.all(
              color: purchased ? Colors.teal : Colors.teal,
              width: 2,
            ),
          ),
          child: purchased
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
      title: Text(
        item.name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          decoration: purchased ? TextDecoration.lineThrough : null,
          color: purchased ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        'Cantitate: ${item.quantity}'
        '${item.category != null ? "  •  ${item.category}" : ""}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.priceEstimate != null)
            Text(
              '${item.priceEstimate!.toStringAsFixed(0)} lei',
              style: TextStyle(
                color: Colors.teal.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

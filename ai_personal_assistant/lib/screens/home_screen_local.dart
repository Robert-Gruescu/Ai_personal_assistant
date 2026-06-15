import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../services/local_assistant_service.dart';
import '../core/services/services.dart';
import '../core/services/widget_service.dart';
import 'data_sheets.dart';

// ─── Model classes ────────────────────────────────────────────────────────────

class Session {
  String id;
  String title;
  List<Message> messages;

  /// Mesajele acestei conversații au fost încărcate din baza de date?
  /// (lazy loading — încărcăm mesajele doar când conversația e deschisă).
  bool loaded;

  Session({
    required this.id,
    required this.title,
    List<Message>? messages,
    this.loaded = false,
  }) : messages = messages ?? [];
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
  /// Comută pe ecranul voice-first (apelat din setări). Opțional.
  final VoidCallback? onSwitchToVoice;

  const HomeScreen({super.key, this.onSwitchToVoice});

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
  bool isGoogleConnected = false;
  String? googleEmail;

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
  final WidgetService _widget = WidgetService();
  final GoogleAuthService _googleAuth = GoogleAuthService();

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

  Message _welcomeMessage() => Message(
    text:
        'Salut! Sunt ASIS, asistentul tău personal vocal. Totul rulează local pe telefon! Cum te pot ajuta?',
    isUser: false,
  );

  void _createInitialSession() {
    final s = Session(
      id: _generateUUID(),
      title: 'Conversație Nouă',
      messages: [_welcomeMessage()],
      loaded: true,
    );
    sessions.add(s);
    sessionId = s.id;
  }

  /// Încarcă din baza de date lista conversațiilor salvate (lazy: doar titlurile;
  /// mesajele se încarcă la deschiderea fiecărei conversații). Se apelează după
  /// inițializarea serviciilor (deci baza de date e gata).
  Future<void> _loadSessions() async {
    try {
      final list = await _service.getConversationList();

      // Sesiunile salvate (lazy: doar titlurile, fără mesaje) pentru bara laterală.
      final saved = list
          .map(
            (c) => Session(
              id: c['id'] as String,
              title: (c['title'] as String?) ?? 'Conversație',
              loaded: false,
            ),
          )
          .toList();

      // COMPORTAMENT: la pornirea aplicației deschidem MEREU o conversație nouă
      // (nu ultima conversație). Conversațiile vechi rămân accesibile în bara
      // laterală. Dacă cea mai recentă e deja goală (o conversație nouă
      // neîncepută), o refolosim — ca să nu acumulăm conversații goale la
      // fiecare pornire.
      final bool firstIsEmpty =
          saved.isNotEmpty && ((list.first['message_count'] as int?) ?? 0) == 0;

      if (firstIsEmpty) {
        final active = saved.first;
        active.messages = [_welcomeMessage()];
        active.loaded = true;
        await _service.switchConversation(active.id);
        if (!mounted) return;
        setState(() {
          sessions = saved;
          sessionId = active.id;
        });
      } else {
        final newId = await _service.createConversation(title: 'Conversație Nouă');
        final newSession = Session(
          id: newId,
          title: 'Conversație Nouă',
          messages: [_welcomeMessage()],
          loaded: true,
        );
        if (!mounted) return;
        setState(() {
          sessions = [newSession, ...saved];
          sessionId = newId;
        });
      }
    } catch (e) {
      // În caz de eroare, păstrăm conversația-placeholder locală.
    }
  }

  Future<void> _initializeServices() async {
    setState(() => statusText = '🔄 Inițializez serviciile...');

    try {
      await _service.initialize();

      // Încarcă conversațiile salvate din baza de date locală.
      await _loadSessions();

      final apiKey = await _config.geminiApiKey;
      isApiKeyConfigured = apiKey != null && apiKey.isNotEmpty;

      // Reconectare silențioasă la Google (dacă utilizatorul s-a conectat deja).
      isGoogleConnected = await _googleAuth.signInSilently();
      googleEmail = _googleAuth.userEmail;
      if (isGoogleConnected) _service.syncGoogleEmail();

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
    // NU apelăm dispose() pe STT/TTS: sunt servicii Singleton partajate cu
    // ecranul Voce (le-ar închide motorul și pentru celălalt ecran). Doar oprim
    // orice activitate în curs când părăsim ecranul.
    _stt.stopListening();
    _tts.stop();
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
  Future<void> _createNewSession() async {
    // Evită acumularea de conversații goale: dacă cea curentă nu are mesaje
    // de la utilizator, o refolosim în loc să creăm alta.
    if (sessions.isNotEmpty && !_currentSession.messages.any((m) => m.isUser)) {
      setState(() => statusText = 'Folosește conversația curentă (goală).');
      return;
    }

    final newId = await _service.createConversation(title: 'Conversație Nouă');
    if (!mounted) return;
    setState(() {
      sessions.insert(
        0,
        Session(
          id: newId,
          title: 'Conversație Nouă',
          messages: [_welcomeMessage()],
          loaded: true,
        ),
      );
      sessionId = newId;
      statusText = 'Sesiune nouă creată.';
    });
  }

  Future<void> _switchSession(String id) async {
    await _service.switchConversation(id);

    // Lazy: încarcă mesajele conversației doar la prima deschidere.
    final s = sessions.firstWhere((x) => x.id == id);
    if (!s.loaded) {
      final msgs = await _service.getConversationMessages(id);
      s.messages = msgs
          .map((m) => Message(text: m['content'] ?? '', isUser: m['role'] == 'user'))
          .toList();
      if (s.messages.isEmpty) s.messages.add(_welcomeMessage());
      s.loaded = true;
    }

    if (!mounted) return;
    setState(() {
      sessionId = id;
      statusText = 'Am schimbat conversația.';
    });
    _scrollToBottom();
  }

  Future<void> _deleteSession(String id) async {
    await _service.deleteConversation(id);
    if (!mounted) return;
    setState(() => sessions.removeWhere((s) => s.id == id));

    if (sessionId == id) {
      if (sessions.isNotEmpty) {
        await _switchSession(sessions.first.id);
      } else {
        await _createNewSession();
      }
    }
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
        _service.updateConversationTitle(sessionId, _currentSession.title);
      }
    });
    _scrollToBottom();

    try {
      final result = await _service.sendMessage(text);

      // Actualizează widget-ul după fiecare mesaj
      await _widget.updateWidget();

      setState(() {
        isProcessing = false;
        _currentSession.messages.add(
          Message(text: result.response, isUser: false),
        );
        statusText = '🎤 Apasă pe microfon pentru a continua';
      });
      _scrollToBottom();
      // Popup cu linkuri de produs (dacă a fost o căutare cu rezultate).
      if (mounted) showProductLinksIfAny(context, result.action);
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
        _service.updateConversationTitle(sessionId, _currentSession.title);
      }
    });
    _scrollToBottom();

    try {
      final result = await _service.sendMessage(text);

      // Actualizează widget-ul după fiecare mesaj
      await _widget.updateWidget();

      setState(() {
        isProcessing = false;
        _currentSession.messages.add(
          Message(text: result.response, isUser: false),
        );
        statusText = '✅ Scrie un mesaj sau apasă pe microfon';
      });
      _scrollToBottom();
      // Popup cu linkuri de produs (dacă a fost o căutare cu rezultate).
      if (mounted) showProductLinksIfAny(context, result.action);
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

  void _showTasksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TasksSheet(
        db: DatabaseService(),
        onChanged: () => _widget.updateWidget(),
      ),
    );
  }

  void _showShoppingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShoppingSheet(
        db: DatabaseService(),
        onChanged: () => _widget.updateWidget(),
      ),
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

  Future<void> _connectGoogle() async {
    if (mounted) {
      setState(() => statusText = '🔄 Conectare la Google...');
    }
    final ok = await _googleAuth.signIn();
    if (ok) _service.syncGoogleEmail();
    if (mounted) {
      setState(() {
        isGoogleConnected = ok;
        googleEmail = _googleAuth.userEmail;
        statusText = ok
            ? '✅ Conectat la Google: $googleEmail'
            : '⚠️ Conectarea la Google a eșuat';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Cont Google conectat: $googleEmail. Întâlnirile vor avea link Meet real.'
                : 'Conectarea la Google a eșuat. Verifică configurarea OAuth.',
          ),
        ),
      );
    }
  }

  Future<void> _disconnectGoogle() async {
    await _googleAuth.signOut();
    if (mounted) {
      setState(() {
        isGoogleConnected = false;
        googleEmail = null;
      });
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Setări'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onSwitchToVoice != null)
              ListTile(
                leading: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Comută pe modul Voce'),
                subtitle: const Text('Asistent vocal, hands-free'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  widget.onSwitchToVoice!();
                },
              ),
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
              leading: Icon(
                Icons.video_call,
                color: isGoogleConnected ? Colors.green : null,
              ),
              title: const Text('Cont Google (Meet, Calendar, Gmail)'),
              subtitle: Text(
                isGoogleConnected
                    ? 'Conectat: ${googleEmail ?? ""}'
                    : 'Neconectat — necesar pentru Meet real și citire/trimitere Gmail',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                if (isGoogleConnected) {
                  _disconnectGoogle();
                } else {
                  _connectGoogle();
                }
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
                  await _widget.updateWidget();
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
                      IconButton(
                        onPressed: !isProcessing ? _sendTextMessage : null,
                        icon: const Icon(Icons.send),
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 8),
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
  // Sidebar drawer
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

        Row(
          children: [
            Expanded(
              child: _SidebarActionButton(
                icon: Icons.checklist_rounded,
                label: 'Task-uri',
                color: Colors.indigo,
                onTap: () {
                  Navigator.pop(context);
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

        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context); // închide bara laterală automat
            _createNewSession();
          },
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
                  onTap: () {
                    Navigator.pop(context); // închide bara laterală automat
                    _switchSession(s.id);
                  },
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

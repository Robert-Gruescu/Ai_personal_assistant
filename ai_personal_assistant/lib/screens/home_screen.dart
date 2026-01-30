import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/assistant_service.dart';

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
  bool isServerOnline = false;

  String statusText = "Verificare conexiune...";

  String sessionId = "";
  List<Session> sessions = [];

  bool showSettings = false;
  String theme = "light";
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Audio
  AudioRecorder? _recorder;
  final AudioPlayer _player = AudioPlayer();
  String? _recordingPath;

  // Service
  final AssistantService _service = AssistantService();

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

    // Verificăm conexiunea la server
    _checkServerConnection();

    // Solicităm permisiuni
    _requestPermissions();
  }

  void _createInitialSession() {
    var newSession = Session(id: _generateUUID(), title: "Conversație Nouă");
    newSession.messages.add(
      Message(
        text:
            "Salut! Sunt ASIS, asistentul tău personal vocal. Cum te pot ajuta?",
        isUser: false,
      ),
    );
    sessions.add(newSession);
    sessionId = newSession.id;
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
  }

  Future<void> _checkServerConnection() async {
    final online = await _service.checkHealth();
    setState(() {
      isServerOnline = online;
      statusText = online
          ? "🎤 Ține apăsat pe microfon pentru a vorbi"
          : "⚠️ Serverul nu este disponibil. Verifică dacă backend-ul rulează.";
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _recorder?.dispose();
    _player.dispose();
    _textController.dispose();
    _scrollController.dispose();
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
  }

  void _switchSession(String id) {
    setState(() {
      sessionId = id;
      statusText = "Am schimbat conversația.";
    });
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

  // --- Înregistrare Audio ---
  Future<void> _startRecording() async {
    try {
      _recorder = AudioRecorder();

      if (!await _recorder!.hasPermission()) {
        setState(() {
          statusText = "⚠️ Permisiune microfon necesară!";
        });
        await Permission.microphone.request();
        return;
      }

      final dir = await getTemporaryDirectory();
      // Use forward slashes for cross-platform compatibility
      _recordingPath =
          '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      print('📁 Recording path: $_recordingPath');

      // Use higher quality settings for better speech recognition
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000, // 16kHz is optimal for speech recognition
          numChannels: 1, // Mono is better for speech
          bitRate: 256000, // Higher bit rate for clarity
        ),
        path: _recordingPath!,
      );

      setState(() {
        isRecording = true;
        statusText = "🎤 Te ascult... Eliberează pentru a trimite";
      });
    } catch (e) {
      print('❌ Start recording error: $e');
      setState(() {
        statusText = "⚠️ Eroare la pornirea înregistrării: $e";
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder?.stop();
      print('📁 Recording stopped, path: $path');
      _recorder?.dispose();
      _recorder = null;

      setState(() {
        isRecording = false;
        isProcessing = true;
        statusText = "🔄 Procesez mesajul tău...";
      });

      if (path != null && path.isNotEmpty) {
        _recordingPath = path;
        await _processRecording();
      } else {
        print('❌ Recording path is null or empty');
        setState(() {
          isProcessing = false;
          statusText = "⚠️ Nu am putut înregistra.";
        });
      }
    } catch (e) {
      print('❌ Stop recording error: $e');
      setState(() {
        isProcessing = false;
        statusText = "⚠️ Eroare la oprirea înregistrării: $e";
      });
    }
  }

  Future<void> _processRecording() async {
    if (_recordingPath == null) {
      print('❌ Recording path is null');
      return;
    }

    try {
      print('📤 Processing recording: $_recordingPath');
      final file = File(_recordingPath!);
      if (!await file.exists()) {
        print('❌ File does not exist: $_recordingPath');
        setState(() {
          isProcessing = false;
          statusText = "⚠️ Fișierul audio nu a fost creat.";
        });
        return;
      }

      print('📤 File exists, size: ${await file.length()} bytes');
      print('📤 Sending to server...');

      final result = await _service.processVoice(file);
      print(
        '📥 Server response: success=${result.success}, transcription="${result.transcription}", error=${result.error}',
      );

      setState(() {
        isProcessing = false;

        if (result.success) {
          print('✅ Voice processing successful');
          // Adaugă mesajul utilizatorului
          if (result.transcription.isNotEmpty) {
            _currentSession.messages.add(
              Message(text: result.transcription, isUser: true),
            );

            // Actualizează titlul sesiunii
            if (_currentSession.title == "Conversație Nouă" &&
                result.transcription.length > 3) {
              _currentSession.title = result.transcription.length > 30
                  ? '${result.transcription.substring(0, 30)}...'
                  : result.transcription;
            }
          }

          // Adaugă răspunsul asistentului
          _currentSession.messages.add(
            Message(text: result.response, isUser: false),
          );

          statusText = "✅ Ține apăsat pe microfon pentru a continua";
          _scrollToBottom();

          // Redă răspunsul audio
          if (result.audioBase64 != null) {
            _playAudioFromBase64(result.audioBase64!);
          }
        } else {
          print('❌ Voice processing failed: ${result.error}');
          statusText = "⚠️ ${result.error ?? 'Eroare la procesare'}";
        }
      });

      // Șterge fișierul temporar
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      print('❌ Processing exception: $e');
      setState(() {
        isProcessing = false;
        statusText = "⚠️ Eroare: $e";
      });
    }
  }

  Future<void> _playAudioFromBase64(String base64Audio) async {
    try {
      setState(() => isPlaying = true);

      final bytes = base64Decode(base64Audio);
      await _player.play(BytesSource(bytes));

      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => isPlaying = false);
        }
      });
    } catch (e) {
      setState(() => isPlaying = false);
    }
  }

  // --- Trimitere text (fallback) ---
  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

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

    final result = await _service.sendMessage(text);

    setState(() {
      isProcessing = false;

      if (result.success) {
        _currentSession.messages.add(
          Message(text: result.response, isUser: false),
        );
        statusText = "✅ Ține apăsat pe microfon sau scrie un mesaj";
        _scrollToBottom();

        if (result.audioBase64 != null) {
          _playAudioFromBase64(result.audioBase64!);
        }
      } else {
        statusText = "⚠️ Eroare la trimitere";
      }
    });
  }

  Color _getOrbColor() {
    if (isProcessing) return Colors.orange;
    if (isRecording) return Colors.red;
    if (isPlaying) return Colors.green;
    if (!isServerOnline) return Colors.grey;
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
                            color: isServerOnline ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isServerOnline ? "Online" : "Offline",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _checkServerConnection,
                          tooltip: "Verifică conexiunea",
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
                                    hintText: "Sau scrie un mesaj...",
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
                                  enabled: isServerOnline && !isProcessing,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Send button
                            IconButton(
                              onPressed: isServerOnline && !isProcessing
                                  ? _sendTextMessage
                                  : null,
                              icon: const Icon(Icons.send),
                              color: Colors.indigo,
                            ),
                            const SizedBox(width: 8),

                            // Mic button - VOICE INPUT
                            GestureDetector(
                              onLongPressStart: isServerOnline && !isProcessing
                                  ? (_) => _startRecording()
                                  : null,
                              onLongPressEnd: isRecording
                                  ? (_) => _stopRecording()
                                  : null,
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
                                            ? Icons.mic
                                            : (isProcessing
                                                  ? Icons.hourglass_empty
                                                  : (isPlaying
                                                        ? Icons.volume_up
                                                        : Icons.mic_none)),
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
                          "Ține apăsat pe microfon pentru a vorbi",
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
          "Asistent Personal Vocal",
          style: TextStyle(fontSize: 12, color: Colors.grey),
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
                // Buton de copiere pentru mesajele AI
                if (!msg.isUser)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: msg.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Text copiat în clipboard!'),
                            duration: Duration(seconds: 2),
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
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
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

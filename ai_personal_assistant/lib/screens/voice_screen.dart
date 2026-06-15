import 'dart:math';
import 'package:flutter/material.dart';
import '../services/local_assistant_service.dart';
import '../core/services/services.dart';
import '../core/services/widget_service.dart';
import 'data_sheets.dart';

/// Stările vizuale ale asistentului vocal.
enum VoiceState { idle, listening, processing, speaking }

/// Ecran VOICE-FIRST: interacțiune doar prin voce, hands-free.
/// Apeși microfonul → vorbești o comandă → asistentul execută și răspunde cu voce.
/// Inelul animat pulsează diferit în funcție de stare (în special reactiv la
/// sunetul vocii tale când te ascultă).
class VoiceScreen extends StatefulWidget {
  /// Comută pe ecranul clasic de chat (apelat din setări).
  final VoidCallback onSwitchToChat;

  const VoiceScreen({super.key, required this.onSwitchToChat});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with SingleTickerProviderStateMixin {
  final LocalAssistantService _service = LocalAssistantService();
  final SpeechToTextService _stt = SpeechToTextService();
  final TextToSpeechService _tts = TextToSpeechService();
  final ConfigService _config = ConfigService();
  final GoogleAuthService _googleAuth = GoogleAuthService();
  final DatabaseService _db = DatabaseService();
  final WidgetService _widget = WidgetService();

  VoiceState _state = VoiceState.idle;
  String _status = 'Apasă pe microfon pentru a începe.';
  double _level = 0.0; // nivel de sunet normalizat 0..1 (cu netezire)
  bool _ready = false;

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _initServices();
  }

  Future<void> _initServices() async {
    await _service.initialize();

    _tts.onStart = () {
      if (mounted) setState(() => _setState(VoiceState.speaking, 'Vorbesc...'));
    };
    _tts.onComplete = () {
      if (mounted) _goIdle();
    };

    _stt.onResult = (text) {
      if (text.trim().isNotEmpty) _handleResult(text);
    };
    _stt.onError = (error) {
      if (mounted) {
        _goIdle(status: 'Nu am înțeles. Apasă din nou microfonul.');
      }
    };
    _stt.onListeningStarted = () {
      if (mounted) {
        setState(() => _setState(VoiceState.listening, 'Te ascult...'));
      }
    };
    _stt.onListeningStopped = () {
      // dacă s-a oprit ascultarea fără rezultat și nu procesăm, revenim în repaus
      if (mounted && _state == VoiceState.listening) {
        // așteptăm eventualul onResult; dacă nu vine, _goIdle din onError
      }
    };
    _stt.onSoundLevel = (level) {
      if (!mounted || _state != VoiceState.listening) return;
      // Normalizează (Android dă aprox. 0..10+) și netezește pentru un puls fluid.
      final norm = (level.clamp(0.0, 12.0)) / 12.0;
      setState(() => _level = _level * 0.6 + norm * 0.4);
    };

    // Reconectare silențioasă Google (pentru email/calendar) + sync email AI.
    final connected = await _googleAuth.signInSilently();
    if (connected) _service.syncGoogleEmail();

    if (mounted) {
      setState(() {
        _ready = true;
        _status = 'Apasă pe microfon pentru a începe.';
      });
    }
  }

  void _setState(VoiceState s, String status) {
    _state = s;
    _status = status;
  }

  void _goIdle({String status = 'Apasă pe microfon pentru a începe.'}) {
    setState(() {
      _state = VoiceState.idle;
      _status = status;
      _level = 0.0;
    });
  }

  Future<void> _toggleMic() async {
    if (!_ready) return;

    // Cât timp procesăm răspunsul AI, ignorăm apăsările pe microfon, ca să nu
    // pornim o ascultare nouă peste cererea în curs (ar suprapune STT cu TTS-ul
    // care urmează). Revenirea din „processing” se face automat în _handleResult.
    if (_state == VoiceState.processing) return;

    // Dacă vorbește acum, oprește vocea și revino în repaus.
    if (_state == VoiceState.speaking) {
      await _service.stopSpeaking();
      _goIdle();
      return;
    }

    if (_state == VoiceState.listening) {
      // Apeși din nou = oprești ascultarea. Doar oprim motorul; rezultatul FINAL
      // (mai exact decât cel parțial) vine prin callback-ul onResult și e procesat
      // o singură dată. NU procesăm aici manual, ca să evităm dubla procesare.
      await _stt.stopListening();
      // Plasă de siguranță: dacă nu vine niciun rezultat final, revenim în repaus.
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted && _state == VoiceState.listening) _goIdle();
      });
      return;
    }

    // idle → pornește ascultarea
    setState(() => _setState(VoiceState.listening, 'Te ascult...'));
    final ok = await _service.startListening();
    if (!ok && mounted) {
      _goIdle(status: 'Nu pot accesa microfonul. Verifică permisiunile.');
    }
  }

  Future<void> _handleResult(String text) async {
    // Protecție anti-dublură: dacă deja procesăm sau vorbim, ignorăm.
    if (_state == VoiceState.processing || _state == VoiceState.speaking) return;
    if (text.trim().isEmpty) {
      _goIdle();
      return;
    }
    setState(() => _setState(VoiceState.processing, 'Mă gândesc...'));
    try {
      final response = await _service.sendMessage(text);
      // TTS.onStart va comuta în starea „speaking”.
      await _service.speak(response.response);
      // Dacă din vreun motiv TTS nu pornește, revenim în repaus.
      if (mounted && _state == VoiceState.processing) _goIdle();
    } catch (e) {
      if (mounted) _goIdle(status: 'A apărut o eroare. Încearcă din nou.');
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    // STT/TTS sunt Singleton partajate cu ecranul Chat — nu le închidem aici,
    // doar oprim orice activitate în curs la părăsirea ecranului.
    _stt.stopListening();
    _tts.stop();
    super.dispose();
  }

  // ── Culori în funcție de stare ──────────────────────────────────────────
  List<Color> get _ringColors {
    switch (_state) {
      case VoiceState.listening:
        return const [
          Color(0xFF6D5DF6),
          Color(0xFF46C2FF),
          Color(0xFF6D5DF6),
        ];
      case VoiceState.processing:
        return const [
          Color(0xFFFFA63D),
          Color(0xFFFF5E8A),
          Color(0xFFFFA63D),
        ];
      case VoiceState.speaking:
        return const [
          Color(0xFF36D1A6),
          Color(0xFF46C2FF),
          Color(0xFF8E7BFF),
          Color(0xFF36D1A6),
        ];
      case VoiceState.idle:
        return const [
          Color(0xFFEC6EAD),
          Color(0xFFFFB36B),
          Color(0xFFFFE16B),
          Color(0xFF7BE0AD),
          Color(0xFF6DA8FF),
          Color(0xFF9D7BFF),
          Color(0xFFEC6EAD),
        ];
    }
  }

  IconData get _centerIcon {
    switch (_state) {
      case VoiceState.listening:
        return Icons.mic_rounded;
      case VoiceState.processing:
        return Icons.more_horiz_rounded;
      case VoiceState.speaking:
        return Icons.graphic_eq_rounded;
      case VoiceState.idle:
        return Icons.monitor_heart_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const [Color(0xFF12121A), Color(0xFF1A1B2E)]
        : const [Color(0xFFEEF1FF), Color(0xFFF7F4FF)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bg,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Bara de sus ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    Text(
                      'ASIS',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1E2147),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.checklist_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF6B6F8D),
                      ),
                      onPressed: _showTasks,
                      tooltip: 'Task-uri',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.shopping_cart_outlined,
                        color: isDark ? Colors.white70 : const Color(0xFF6B6F8D),
                      ),
                      onPressed: _showShopping,
                      tooltip: 'Lista de cumpărături',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.settings_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF6B6F8D),
                      ),
                      onPressed: _showSettings,
                      tooltip: 'Setări',
                    ),
                  ],
                ),
              ),

              // ── Inelul animat ──
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _toggleMic,
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (context, _) {
                        return CustomPaint(
                          size: const Size(260, 260),
                          painter: _RingPainter(
                            colors: _ringColors,
                            t: _anim.value,
                            state: _state,
                            level: _level,
                            isDark: isDark,
                          ),
                          child: SizedBox(
                            width: 260,
                            height: 260,
                            child: Center(
                              child: Icon(
                                _centerIcon,
                                size: 56,
                                color: const Color(0xFF8E7BFF),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // ── Status ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    color: isDark ? Colors.white70 : const Color(0xFF5A5E7A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // ── Buton microfon ──
              GestureDetector(
                onTap: _toggleMic,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6D5DF6), Color(0xFF8E7BFF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6D5DF6).withValues(alpha: 0.45),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _state == VoiceState.listening
                        ? Icons.stop_rounded
                        : _state == VoiceState.speaking
                        ? Icons.volume_up_rounded
                        : Icons.mic_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ── Task-uri & Cumpărături (panouri partajate cu modul chat) ────────────
  void _showTasks() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TasksSheet(
        db: _db,
        onChanged: () => _widget.updateWidget(),
      ),
    );
  }

  void _showShopping() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShoppingSheet(
        db: _db,
        onChanged: () => _widget.updateWidget(),
      ),
    );
  }

  // ── SETĂRI (pentru modul voce) ──────────────────────────────────────────
  void _showSettings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('Comută pe modul Chat (clasic)'),
              subtitle: const Text('Interfață cu text și liste'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onSwitchToChat();
              },
            ),
            ListTile(
              leading: Icon(
                _googleAuth.isSignedIn ? Icons.verified_user : Icons.login,
                color: _googleAuth.isSignedIn ? Colors.green : null,
              ),
              title: Text(
                _googleAuth.isSignedIn
                    ? 'Cont Google conectat'
                    : 'Conectează-te cu Google',
              ),
              subtitle: Text(
                _googleAuth.isSignedIn
                    ? '${_googleAuth.userEmail ?? ""} — apasă pentru deconectare'
                    : 'Pentru Meet, Calendar și Gmail',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                if (_googleAuth.isSignedIn) {
                  await _googleAuth.signOut();
                } else {
                  final ok = await _googleAuth.signIn();
                  if (ok) _service.syncGoogleEmail();
                }
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: const Text('Cheie API Gemini'),
              onTap: () {
                Navigator.pop(ctx);
                _showApiKeyDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Configurare Email (SMTP)'),
              subtitle: const Text('Rezervă, dacă nu folosești Google'),
              onTap: () {
                Navigator.pop(ctx);
                _showEmailConfigDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Șterge toate datele'),
              subtitle: const Text('Conversații, task-uri, cumpărături'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmClearData();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEmailConfigDialog() async {
    final savedEmail = await _config.smtpUser;
    final savedPassword = await _config.smtpPassword;
    final userCtrl = TextEditingController(text: savedEmail ?? '');
    final passCtrl = TextEditingController(text: savedPassword ?? '');
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurare Email'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Recomandat: conectează-te cu Google (mai sus) — atunci nu mai e '
                'nevoie de parolă. Această configurare e doar rezervă (SMTP Gmail). '
                'Folosește o parolă de aplicație dacă ai 2FA.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email (Gmail)',
                  hintText: 'exemplu@gmail.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = userCtrl.text.trim();
              final password = passCtrl.text;
              if (email.isEmpty || password.isEmpty) return;
              await _config.setEmailConfig(
                smtpUser: email,
                smtpPassword: password,
              );
              await _service.reloadEmailConfig();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmare'),
        content: const Text('Ești sigur că vrei să ștergi toate datele?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.clearAllData();
      await _widget.updateWidget();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Toate datele au fost șterse.')),
        );
      }
    }
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cheie API Gemini'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Lipește cheia API aici',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                await _config.setGeminiApiKey(key);
                await _service.configureApiKey(key);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
  }
}

/// Desenează inelul cu gradient, scalat/animat în funcție de stare.
class _RingPainter extends CustomPainter {
  final List<Color> colors;
  final double t; // 0..1 progres animație continuă
  final VoiceState state;
  final double level; // nivel sunet 0..1 (la ascultare)
  final bool isDark;

  _RingPainter({
    required this.colors,
    required this.t,
    required this.state,
    required this.level,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Factor de „puls” în funcție de stare.
    double pulse;
    switch (state) {
      case VoiceState.listening:
        pulse = 0.86 + level * 0.14; // reactiv la voce
        break;
      case VoiceState.speaking:
        pulse = 0.9 + 0.06 * sin(t * 2 * pi * 2); // ritmic
        break;
      case VoiceState.processing:
        pulse = 0.9 + 0.03 * sin(t * 2 * pi * 3);
        break;
      case VoiceState.idle:
        pulse = 0.92 + 0.03 * sin(t * 2 * pi); // respirație lentă
        break;
    }

    final radius = maxRadius * pulse;
    final stroke = 16.0;

    // Rotația gradientului (mai rapidă la procesare).
    final rotation = state == VoiceState.processing
        ? t * 2 * pi * 1.5
        : t * 2 * pi * 0.4;

    final ringRect = Rect.fromCircle(
      center: center,
      radius: radius - stroke / 2,
    );

    // Halou exterior (glow) — mai puternic când e activ.
    final glowAlpha = state == VoiceState.idle ? 0.18 : 0.30;
    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: glowAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(center, radius, glowPaint);

    // Cercul alb interior.
    final innerPaint = Paint()
      ..color = isDark ? const Color(0xFF20223A) : Colors.white;
    canvas.drawCircle(center, radius - stroke, innerPaint);

    // Inelul cu gradient.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(rotation),
      ).createShader(ringRect);
    canvas.drawArc(ringRect, 0, 2 * pi, false, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.t != t ||
      old.state != state ||
      old.level != level ||
      old.colors != colors;
}

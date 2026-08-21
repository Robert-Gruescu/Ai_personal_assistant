import 'dart:math';
import 'package:flutter/material.dart';
import '../services/local_assistant_service.dart';
import '../core/services/services.dart';
import '../core/services/widget_service.dart';
import 'data_sheets.dart';
import 'settings_widgets.dart';
import '../main.dart' show themeNotifier, setAppTheme;

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
    with TickerProviderStateMixin {
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

  // Pentru afișarea stării în pagina de Setări.
  bool _apiKeyConfigured = false;
  bool _emailConfigured = false;

  /// Pulsul inelului (respirație / reacție la voce).
  late final AnimationController _anim;

  /// Rotația lentă și continuă a arcului, ca pe site.
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
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

    await _loadConfigFlags();

    if (mounted) {
      setState(() {
        _ready = true;
        _status = 'Apasă pe microfon pentru a începe.';
      });
    }
  }

  /// Reîncarcă starea „configurat" pentru cheia API și email (pentru bifele din Setări).
  Future<void> _loadConfigFlags() async {
    final apiKey = await _config.geminiApiKey;
    final email = await _config.smtpUser;
    if (!mounted) return;
    setState(() {
      _apiKeyConfigured = apiKey != null && apiKey.isNotEmpty;
      _emailConfigured = email != null && email.isNotEmpty;
    });
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
      // Popup cu linkuri de produs (dacă a fost o căutare cu rezultate).
      if (mounted) showProductLinksIfAny(context, response.action);
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
    _spin.dispose();
    // STT/TTS sunt Singleton partajate cu ecranul Chat — nu le închidem aici,
    // doar oprim orice activitate în curs la părăsirea ecranului.
    _stt.stopListening();
    _tts.stop();
    super.dispose();
  }

  // ── Culori în funcție de stare (aceeași paletă ca pe site) ─────────────
  Color get _stateColor {
    switch (_state) {
      case VoiceState.idle:
        return const Color(0xFF5C6BFF);
      case VoiceState.listening:
        return const Color(0xFF8E7BFF);
      case VoiceState.processing:
        return const Color(0xFF4FD1C5);
      case VoiceState.speaking:
        return const Color(0xFFF0A020);
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
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
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
                    HeaderIconButton(
                      icon: Icons.chat_bubble_rounded,
                      tooltip: 'Mod Chat',
                      isDark: isDark,
                      onTap: widget.onSwitchToChat,
                    ),
                    const SizedBox(width: 6),
                    HeaderIconButton(
                      icon: Icons.checklist_rounded,
                      tooltip: 'Task-uri',
                      isDark: isDark,
                      onTap: _showTasks,
                    ),
                    const SizedBox(width: 6),
                    HeaderIconButton(
                      icon: Icons.shopping_cart_rounded,
                      tooltip: 'Cumpărături',
                      isDark: isDark,
                      onTap: _showShopping,
                    ),
                    const SizedBox(width: 6),
                    HeaderIconButton(
                      icon: Icons.settings_rounded,
                      tooltip: 'Setări',
                      isDark: isDark,
                      onTap: _openSettingsPage,
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
                      animation: Listenable.merge([_anim, _spin]),
                      builder: (context, _) {
                        return CustomPaint(
                          size: const Size(260, 260),
                          painter: _RingPainter(
                            color: _stateColor,
                            t: _anim.value,
                            spin: _spin.value,
                            state: _state,
                            level: _level,
                          ),
                          child: const SizedBox(
                            width: 260,
                            height: 260,
                            child: Center(
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: Image(
                                  image: AssetImage(
                                    'assets/icon/app_icon_foreground.png',
                                  ),
                                  fit: BoxFit.contain,
                                ),
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

  // ── SETĂRI (pagină full-screen, identică ca stil cu modul Chat) ──────────
  Future<void> _openSettingsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageCtx, setLocal) {
            final isDark = themeNotifier.value == ThemeMode.dark;
            void refresh() {
              if (mounted) setState(() {});
              setLocal(() {});
            }

            return Scaffold(
              backgroundColor: isDark
                  ? Colors.grey.shade900
                  : Colors.grey.shade100,
              appBar: AppBar(
                title: const Text('Setări'),
                backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
                foregroundColor: isDark ? Colors.white : Colors.black87,
                elevation: 0,
              ),
              body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  SettingsSectionTitle('Conturi și conectare', isDark: isDark),
                  SettingsCard(
                    isDark: isDark,
                    children: [
                      SettingsTile(
                        isDark: isDark,
                        badgeColor: const Color(0xFF4285F4),
                        badgeIcon: Icons.g_mobiledata_rounded,
                        title: 'Cont Google',
                        subtitle: _googleAuth.isSignedIn
                            ? 'Conectat: ${_googleAuth.userEmail ?? ""}'
                            : 'Meet, Calendar și Gmail',
                        connected: _googleAuth.isSignedIn,
                        onTap: () async {
                          if (_googleAuth.isSignedIn) {
                            await _googleAuth.signOut();
                          } else {
                            final ok = await _googleAuth.signIn();
                            if (ok) _service.syncGoogleEmail();
                          }
                          refresh();
                        },
                      ),
                      SettingsDivider(isDark: isDark),
                      SettingsTile(
                        isDark: isDark,
                        badgeColor: const Color(0xFFEA4335),
                        badgeIcon: Icons.mail_rounded,
                        title: 'Conectare Email',
                        subtitle: _emailConfigured
                            ? 'Configurat (SMTP / Gmail)'
                            : 'Trimitere emailuri (rezervă)',
                        connected: _emailConfigured,
                        onTap: () async {
                          await _showEmailConfigDialog();
                          await _loadConfigFlags();
                          refresh();
                        },
                      ),
                      SettingsDivider(isDark: isDark),
                      SettingsTile(
                        isDark: isDark,
                        badgeColor: const Color(0xFF7E57C2),
                        badgeIcon: Icons.vpn_key_rounded,
                        title: 'Cheie API Gemini',
                        subtitle: _apiKeyConfigured
                            ? 'Configurată'
                            : 'Necesară pentru a folosi asistentul',
                        connected: _apiKeyConfigured,
                        onTap: () async {
                          await _showApiKeyDialog();
                          await _loadConfigFlags();
                          refresh();
                        },
                      ),
                    ],
                  ),
                  SettingsSectionTitle('Aspect', isDark: isDark),
                  SettingsCard(
                    isDark: isDark,
                    children: [
                      SettingsTile(
                        isDark: isDark,
                        badgeColor: const Color(0xFF455A64),
                        badgeIcon: Icons.brightness_6_rounded,
                        title: 'Temă întunecată',
                        subtitle: isDark ? 'Activată' : 'Dezactivată',
                        trailing: Switch(
                          value: isDark,
                          onChanged: (v) async {
                            await setAppTheme(v);
                            refresh();
                          },
                        ),
                        onTap: () async {
                          await setAppTheme(!isDark);
                          refresh();
                        },
                      ),
                    ],
                  ),
                  SettingsSectionTitle('Date', isDark: isDark),
                  SettingsCard(
                    isDark: isDark,
                    children: [
                      SettingsTile(
                        isDark: isDark,
                        badgeColor: const Color(0xFFE53935),
                        badgeIcon: Icons.delete_forever_rounded,
                        title: 'Șterge toate datele',
                        subtitle: 'Conversații, task-uri, cumpărături, memorie',
                        danger: true,
                        onTap: () async {
                          await _confirmClearData();
                          refresh();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showEmailConfigDialog() async {
    final savedEmail = await _config.smtpUser;
    final savedPassword = await _config.smtpPassword;
    final userCtrl = TextEditingController(text: savedEmail ?? '');
    final passCtrl = TextEditingController(text: savedPassword ?? '');
    if (!mounted) return;

    await showDialog(
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

  Future<void> _showApiKeyDialog() {
    final controller = TextEditingController();
    return showDialog(
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

/// Desenează inelul animat, identic cu cel de pe site-ul de prezentare:
/// un arc subțire, cu o breșă, care se rotește lent, un halou colorat în
/// spate și un disc întunecat în mijloc, peste care stă sigla.
class _RingPainter extends CustomPainter {
  /// Culoarea stării curente (repaus / ascultare / gândire / vorbire).
  final Color color;

  /// Progresul pulsului, 0..1 (respirație și reacție la voce).
  final double t;

  /// Progresul rotației arcului, 0..1 (un tur complet la 14 secunde).
  final double spin;

  final VoiceState state;

  /// Nivelul sunetului 0..1, folosit doar cât timp ascultă.
  final double level;

  /// Cât din cerc e desenat (restul rămâne breșă), ca pe site.
  static const double _arcFraction = 0.61;

  /// Violetul haloului din jurul discului — la fel în toate stările.
  static const Color _haloColor = Color(0xFF8E7BFF);

  _RingPainter({
    required this.color,
    required this.t,
    required this.spin,
    required this.state,
    required this.level,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Factor de „puls” în funcție de stare.
    double pulse;
    switch (state) {
      case VoiceState.listening:
        pulse = 0.90 + level * 0.10; // reactiv la voce
        break;
      case VoiceState.speaking:
        pulse = 0.94 + 0.04 * sin(t * 2 * pi * 2); // ritmic
        break;
      case VoiceState.processing:
        pulse = 0.94 + 0.02 * sin(t * 2 * pi * 3);
        break;
      case VoiceState.idle:
        pulse = 0.95 + 0.02 * sin(t * 2 * pi); // respirație lentă
        break;
    }

    final radius = maxRadius * 0.94 * pulse;
    const stroke = 4.5;
    final innerRadius = radius * 0.72;

    // 1. Halou colorat în spate, în tonul stării.
    final glowRadius = radius * 1.32;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.34),
          color.withValues(alpha: 0.10),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 2. Discul din mijloc, cu aura lui violet (ca umbra de pe site).
    final haloPaint = Paint()
      ..color = _haloColor.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawCircle(center, innerRadius, haloPaint);

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()..color = const Color(0xFF141C33),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    // 3. Arcul care se rotește, cu gradient pe lungimea lui.
    final ringRect = Rect.fromCircle(
      center: center,
      radius: radius - stroke / 2,
    );
    final rotation = spin * 2 * pi;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.90),
        ],
        stops: const [0.0, 0.55, 1.0],
        transform: GradientRotation(rotation),
      ).createShader(ringRect);
    canvas.drawArc(
      ringRect,
      rotation,
      2 * pi * _arcFraction,
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.t != t ||
      old.spin != spin ||
      old.state != state ||
      old.level != level ||
      old.color != color;
}

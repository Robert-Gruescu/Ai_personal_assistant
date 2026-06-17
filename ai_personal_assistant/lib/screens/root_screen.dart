import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../main.dart' show navigatorKey;
import '../core/services/config_service.dart';
import '../core/services/database_service.dart';
import '../core/services/widget_service.dart';
import 'voice_screen.dart';
import 'home_screen_local.dart';
import 'data_sheets.dart';

/// Ecranul rădăcină: decide ce interfață se afișează (voce sau chat) pe baza
/// preferinței salvate și permite comutarea între ele din setări.
/// Implicit pornește în modul VOCE (voice-first).
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final ConfigService _config = ConfigService();
  String? _mode; // null = se încarcă preferința
  bool _handlingWidgetTap = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _initWidgetClicks();
  }

  /// Ascultă tap-urile de pe widget-ul din ecranul principal:
  /// zona stângă (asis://tasks) deschide panoul de task-uri,
  /// zona dreaptă (asis://shopping) deschide lista de cumpărături.
  void _initWidgetClicks() {
    // Pornire „la rece": aplicația a fost deschisă chiar din widget.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
    // Pornire „la cald": aplicația era deja deschisă.
    HomeWidget.widgetClicked.listen(_handleWidgetUri);
  }

  void _handleWidgetUri(Uri? uri) {
    if (uri == null) return;
    if (_handlingWidgetTap) return; // evită deschideri multiple la tap-uri repetate
    final host = uri.host;
    if (host != 'tasks' && host != 'shopping') return;
    _handlingWidgetTap = true;

    // Deschidem după frame-ul curent, ca să fim siguri că navigatorul e gata
    // (tap-ul vine dintr-un intent, posibil în mijlocul revenirii în prim-plan).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentState?.overlay?.context;
      if (ctx == null) {
        _handlingWidgetTap = false;
        return;
      }
      void onChanged() => WidgetService().updateWidget();
      final Widget sheet = host == 'tasks'
          ? TasksSheet(db: DatabaseService(), onChanged: onChanged)
          : ShoppingSheet(db: DatabaseService(), onChanged: onChanged);
      try {
        showModalBottomSheet(
          context: ctx,
          isScrollControlled: true,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          builder: (_) => sheet,
        ).whenComplete(() => _handlingWidgetTap = false);
      } catch (e) {
        print('⚠️ Eroare la deschiderea panoului din widget: $e');
        _handlingWidgetTap = false;
      }
    });
  }

  Future<void> _loadMode() async {
    final mode = await _config.screenMode;
    if (mounted) setState(() => _mode = mode);
  }

  Future<void> _switchTo(String mode) async {
    await _config.setScreenMode(mode);
    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_mode == 'chat') {
      return HomeScreen(onSwitchToVoice: () => _switchTo('voice'));
    }
    return VoiceScreen(onSwitchToChat: () => _switchTo('chat'));
  }
}

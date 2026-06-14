import 'package:flutter/material.dart';
import '../core/services/config_service.dart';
import 'voice_screen.dart';
import 'home_screen_local.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMode();
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

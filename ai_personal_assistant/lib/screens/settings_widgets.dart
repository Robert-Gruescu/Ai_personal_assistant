import 'package:flutter/material.dart';

/// Widget-uri UI partajate între ecranul de Chat și ecranul de Voce:
/// butonul rotund din antet + componentele paginii de Setări (titlu de
/// secțiune, card, rând cu badge colorat, separator). Ținute într-un singur
/// loc ca cele două ecrane să arate identic și să nu duplicăm cod.

const Color kVoiceAccent = Color(0xFF8E7BFF);

/// Buton rotund pentru antet (Task-uri / Cumpărături / Chat / Voce).
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDark;

  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = isDark ? kVoiceAccent : Colors.indigo;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: base.withOpacity(isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: base, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Titlu de secțiune (ex. „CONTURI ȘI CONECTARE") din pagina de Setări.
class SettingsSectionTitle extends StatelessWidget {
  final String text;
  final bool isDark;
  const SettingsSectionTitle(this.text, {super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }
}

/// Card alb/întunecat care grupează mai multe rânduri de setări.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  const SettingsCard({super.key, required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// Separator subțire între rândurile dintr-un [SettingsCard].
class SettingsDivider extends StatelessWidget {
  final bool isDark;
  const SettingsDivider({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 68),
      child: Divider(
        height: 1,
        thickness: 0.6,
        color: isDark ? Colors.white12 : Colors.black12,
      ),
    );
  }
}

/// Un rând din pagina de Setări: badge colorat (logo) + titlu + subtitlu +
/// indicator (bifă verde dacă e conectat/configurat, sau chevron).
class SettingsTile extends StatelessWidget {
  final Color badgeColor;
  final IconData badgeIcon;
  final String title;
  final String subtitle;
  final bool connected;
  final bool danger;
  final bool isDark;
  final Widget? trailing;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
    required this.badgeColor,
    required this.badgeIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
    this.connected = false,
    this.danger = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(badgeIcon, color: Colors.white, size: 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: danger
              ? Colors.red
              : (isDark ? Colors.white : Colors.black87),
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
      trailing:
          trailing ??
          (connected
              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
              : const Icon(Icons.chevron_right, size: 22)),
      onTap: onTap,
    );
  }
}
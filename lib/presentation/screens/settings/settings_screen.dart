import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../main.dart' show isSpanishNotifier;

Future<void> _setLang(bool isSpanish) async {
  isSpanishNotifier.value = isSpanish;
  AnalyticsService.instance.logLanguageChanged(isSpanish ? 'es' : 'en');
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('language', isSpanish ? 'es' : 'en');
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          appBar: AppBar(title: Text(s.settingsTitle)),
          body: ListView(
            children: [
              // ── Language ───────────────────────────────────────
              _SectionHeader(s.language),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _LangButton(
                        label: 'English',
                        selected: !isEs,
                        onTap: () => _setLang(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LangButton(
                        label: 'Español',
                        selected: isEs,
                        onTap: () => _setLang(true),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // ── Premium ────────────────────────────────────────
              _SectionHeader('Premium'),
              ValueListenableBuilder<bool>(
                valueListenable: freemiumService.isPremiumNotifier,
                builder: (context, isPremium, _) => isPremium
                  ? ListTile(
                      leading: const Icon(Icons.verified, color: Colors.amber),
                      title: Text(s.premiumActive),
                      subtitle: Text(s.premiumSubtitle),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      _SettingsTile(
                        icon: Icons.star_outline,
                        label: s.getPremium,
                        subtitle: s.premiumSubtitle,
                        onTap: () => IAPService.instance.buy(),
                      ),
                      _SettingsTile(
                        icon: Icons.restore,
                        label: s.restorePurchase,
                        onTap: () => IAPService.instance.restore(),
                      ),
                      if (kDebugMode)
                        _SettingsTile(
                          icon: Icons.bug_report,
                          label: 'Force Premium (DEV)',
                          onTap: () => freemiumService.debugUnlockPremium(),
                        ),
                    ]),
              ),
              const Divider(height: 1),
              // ── Support ────────────────────────────────────────
              _SectionHeader(s.support),
              _SettingsTile(
                icon: Icons.email_outlined,
                label: s.contactSupport,
                onTap: () => _launch('mailto:support@mortgageus.app'),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: s.privacyPolicy,
                onTap: () => _launch('https://mortgageus.app/privacy'),
              ),
              const Divider(height: 1),
              // ── Discover ───────────────────────────────────────
              _SectionHeader(s.discover),
              _SettingsTile(
                icon: Icons.apps_outlined,
                label: 'CalcWise',
                subtitle: s.calcSuite,
                onTap: () => _launch('https://calqwise.com'),
              ),
              _SettingsTile(
                icon: Icons.grid_view_outlined,
                label: isEs ? 'Más apps de CalqWise' : 'More apps by CalqWise',
                subtitle: isEs ? 'Ver todas nuestras calculadoras' : 'See all our calculators',
                onTap: () => _launch('https://play.google.com/store/apps/developer?id=CalqWise'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  s.disclaimer,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(title.toUpperCase(),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
        color: AppTheme.primary, letterSpacing: 0.8)),
  );
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangButton({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    const color = AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          border: Border.all(color: selected ? color : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          )),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.label, this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppTheme.primary),
    title: Text(label),
    subtitle: subtitle != null ? Text(subtitle!) : null,
    trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
    onTap: onTap,
  );
}

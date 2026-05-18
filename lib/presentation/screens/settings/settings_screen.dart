import 'package:calcwise_core/calcwise_core.dart';
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
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        return CalcwiseSettingsScaffold(
          title: s.settingsTitle,
          bottomNavigationBar: const CalcwiseAdFooter(),
          children: [
            // ── Language ───────────────────────────────────────
            CalcwiseSettingsSection(
              title: s.language,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LangButton(
                          label: 'English',
                          selected: !isEs,
                          onTap: () => _setLang(false),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
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
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeService.notifier,
                  builder: (_, mode, __) => CalcwiseSettingsTile(
                    icon: themeModeService.icon,
                    label: themeModeService.label(isSpanish: isEs),
                    onTap: () => themeModeService.toggle(),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            // ── Premium ────────────────────────────────────────
            ValueListenableBuilder<bool>(
              valueListenable: freemiumService.isPremiumNotifier,
              builder: (context, isPremium, _) => CalcwiseSettingsSection(
                title: 'Premium',
                children: isPremium
                    ? [
                        ListTile(
                          leading:
                              const Icon(Icons.verified, color: CalcwiseSemanticColors.warnIcon),
                          title: Text(s.premiumActive),
                          subtitle: Text(s.premiumSubtitle),
                        ),
                      ]
                    : [
                        CalcwiseSettingsTile(
                          icon: Icons.star_rounded,
                          label: s.getPremium,
                          subtitle: s.premiumSubtitle as String?,
                          trailing: '\$2.99',
                          onTap: () => IAPService.instance.buy(),
                        ),
                        CalcwiseSettingsTile(
                          icon: Icons.restore,
                          label: s.restorePurchase,
                          onTap: () => IAPService.instance.restore(),
                        ),
                        if (kDebugMode)
                          CalcwiseSettingsTile(
                            icon: Icons.bug_report,
                            label: 'Force Premium (DEV)',
                            onTap: () => freemiumService.debugUnlockPremium(),
                          ),
                      ],
              ),
            ),
            const Divider(height: 1),
            // ── Support ────────────────────────────────────────
            CalcwiseSettingsSection(
              title: s.support,
              children: [
                CalcwiseSettingsTile(
                  icon: Icons.email_rounded,
                  label: s.contactSupport,
                  onTap: () => _launch('mailto:support@mortgageus.app'),
                ),
                CalcwiseSettingsTile(
                  icon: Icons.privacy_tip_rounded,
                  label: s.privacyPolicy,
                  onTap: () => _launch('https://calqwise.com/privacy'),
                ),
                CalcwiseRateAppTile(
                    label: isEs ? 'Calificar la app' : 'Rate the App'),
              ],
            ),
            const Divider(height: 1),
            // ── Discover ───────────────────────────────────────
            CalcwiseSettingsSection(
              title: s.discover,
              children: [
                CalcwiseSettingsTile(
                  icon: Icons.apps_rounded,
                  label: 'CalcWise',
                  subtitle: s.calcSuite as String?,
                  onTap: () => _launch('https://calqwise.com'),
                ),
                CalcwiseSettingsTile(
                  icon: Icons.grid_view_rounded,
                  label:
                      isEs ? 'Más apps de CalqWise' : 'More apps by CalqWise',
                  subtitle: isEs
                      ? 'Ver todas nuestras calculadoras'
                      : 'See all our calculators',
                  onTap: () => _launch(
                      'https://play.google.com/store/apps/developer?id=CalqWise'),
                ),
              ],
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: Text(
                s.disclaimer,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF475569),
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangButton(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    const color = AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          border: Border.all(color: selected ? color : const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF334155),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }
}

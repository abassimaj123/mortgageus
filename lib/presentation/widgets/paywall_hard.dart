import 'package:flutter/material.dart';
import '../../core/freemium/iap_service.dart';
import '../../core/freemium/freemium_service.dart';
import '../../core/ads/ad_service.dart';
import '../../core/services/ad_free_service.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

class PaywallHard extends StatelessWidget {
  const PaywallHard({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: true,   // Google Play: user must always be able to dismiss
        builder: (_) => const PaywallHard(),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isSpanish, __) {
        final title = isSpanish
            ? 'No dejes que los costos hipotecarios te cuesten miles'
            : 'Don\'t let mortgage costs drain your savings';
        final sub = isSpanish
            ? 'Premium muestra exactamente cómo ahorrar'
            : 'Premium shows exactly how to save more';
        final features = isSpanish
            ? ['💰 Guarda y compara escenarios hipotecarios',
                '📋 Tabla de amortización completa (todos los años)',
                '📊 Historial ilimitado & exportar PDF', '🚫 Sin anuncios — nunca']
            : ['💰 Save & compare mortgage scenarios',
                '📋 Full amortization schedule (all years)',
                '📊 Unlimited history & PDF export', '🚫 Zero ads — ever'];
        const price = r'$4.99';
        final btnPrimary = isSpanish
            ? 'Empezar a ahorrar\n$price (ahorra \$1,000+)'
            : 'Start saving now\n$price (save \$1,000+)';
        final btnReward = isSpanish ? 'Ver anuncio (60 min gratis)' : 'Watch ad (60 min free)';
        final btnSecondary = isSpanish ? 'Ahora no' : 'Not now';

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Colors.orange, size: 32),
                ),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                const SizedBox(height: 6),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 18),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        const SizedBox(width: 8),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      AnalyticsService.instance.logPurchaseStarted();
                      IAPService.instance.buy();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(btnPrimary,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, height: 1.4)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final earned = await AdService.instance.showRewarded();
                      if (!earned) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isSpanish
                                ? 'Anuncio no disponible. Inténtalo de nuevo.'
                                : 'Ad not available. Try again later.'),
                          ),
                        );
                        return;
                      }
                      await freemiumService.activateRewarded();
                      await AdFreeService.instance.unlockForDuration(
                          const Duration(minutes: 60));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(btnReward, style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Opacity(
                    opacity: 0.5,
                    child: Text(btnSecondary,
                        style: const TextStyle(color: Colors.grey, fontSize: 13)),
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

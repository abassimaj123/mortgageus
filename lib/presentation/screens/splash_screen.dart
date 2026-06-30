import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart' show isSpanishNotifier;
import 'onboarding/onboarding_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    return CalcwiseSplash(
        appName: 'Mortgage',
        appSuffix: 'US',
        tagline: isEs
            ? 'Tu camino hacia la casa propia'
            : 'Your path to homeownership',
        chips: isEs
            ? const ['Tasas a 30 años', 'Los 50 estados', 'Amortización']
            : const ['30-Year Rates', 'All 50 States', 'Amortization'],
        badgeSymbol: r'M$',
        badgeIcon: Icons.home_rounded,
        backgroundColor: AppTheme.primary,
        onComplete: () async {
          final done = await isOnboardingComplete('mortgageus');
          if (!context.mounted) return;
          if (!done) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            );
          } else {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        },
      );
  }
}

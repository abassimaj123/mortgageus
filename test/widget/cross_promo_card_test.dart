import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:mortgage_us/presentation/widgets/cross_promo_card.dart';

/// Builds a minimal host for widget tests — no Firebase, no AdMob, no IAP.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: [CalcwiseTheme.light()],
      ),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CrossPromoCard', () {
    testWidgets('renders promo content for free user with no prior dismissal',
        (tester) async {
      await tester.pumpWidget(_host(
        const CrossPromoCard(isPremium: false),
      ));
      // Allow async _check() to complete
      await tester.pumpAndSettle();

      expect(find.text('Salary Calculator'), findsOneWidget);
      expect(find.text('Know your real take-home pay'), findsOneWidget);
    });

    testWidgets('hides entirely for premium user', (tester) async {
      await tester.pumpWidget(_host(
        const CrossPromoCard(isPremium: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Salary Calculator'), findsNothing);
    });

    testWidgets('hides when already dismissed within 7 days', (tester) async {
      // Simulate a recent dismissal
      SharedPreferences.setMockInitialValues({
        'xpromo_mortgageus_salary': DateTime.now().millisecondsSinceEpoch,
      });

      await tester.pumpWidget(_host(
        const CrossPromoCard(isPremium: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Salary Calculator'), findsNothing);
    });

    testWidgets('shows again after 7 days have passed', (tester) async {
      // Simulate a dismissal 8 days ago
      SharedPreferences.setMockInitialValues({
        'xpromo_mortgageus_salary': DateTime.now()
            .subtract(const Duration(days: 8))
            .millisecondsSinceEpoch,
      });

      await tester.pumpWidget(_host(
        const CrossPromoCard(isPremium: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Salary Calculator'), findsOneWidget);
    });

    testWidgets('dismiss button removes card', (tester) async {
      await tester.pumpWidget(_host(
        const CrossPromoCard(isPremium: false),
      ));
      await tester.pumpAndSettle();

      // Card is visible
      expect(find.text('Salary Calculator'), findsOneWidget);

      // Tap the close icon
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Card collapses to SizedBox.shrink()
      expect(find.text('Salary Calculator'), findsNothing);
    });
  });
}

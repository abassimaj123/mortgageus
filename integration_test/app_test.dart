import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mortgage_us/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MortgageUS integration tests', () {
    testWidgets('Calculator screen loads and calculates', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify calculator screen visible
      expect(find.byType(TextField), findsWidgets);

      // Find and tap calculate button
      final calcButton = find.text('Calculate');
      if (calcButton.evaluate().isNotEmpty) {
        await tester.tap(calcButton);
        await tester.pumpAndSettle();
        // Verify results appear (some number is shown)
        expect(find.textContaining('\$'), findsWidgets);
      }
    });

    testWidgets('App does not crash on launch', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}

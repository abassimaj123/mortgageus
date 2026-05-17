import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mortgageus/presentation/screens/calculator/calculator_screen.dart';
import 'common/test_utils.dart';

void main() {
  group('Calculator Screen', () {
    testWidgets('Screen loads without errors', (WidgetTester tester) async {
      await TestUtils.pumpWidget(
        tester,
        const CalculatorScreen(),
      );

      // Verify key widgets are present
      expect(find.byType(TextField), findsWidgets);
      expect(find.byType(CalculatorScreen), findsOneWidget);
    });

    testWidgets('Has input fields for home price and down payment',
        (WidgetTester tester) async {
      await TestUtils.pumpWidget(
        tester,
        const CalculatorScreen(),
      );

      // Should have multiple text fields
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('Can enter home price', (WidgetTester tester) async {
      await TestUtils.pumpWidget(
        tester,
        const CalculatorScreen(),
      );

      // Enter home price
      await TestUtils.enterText(tester, '300000');

      // Verify text was entered
      expect(find.text('300000'), findsOneWidget);
    });

    testWidgets('Has calculate button', (WidgetTester tester) async {
      await TestUtils.pumpWidget(
        tester,
        const CalculatorScreen(),
      );

      // Look for calculate button (common button text)
      expect(
        find.byType(ElevatedButton),
        findsWidgets,
      );
    });
  });
}

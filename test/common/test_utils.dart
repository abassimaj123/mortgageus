import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Common test utilities for MortgageUS and other calculator apps
class TestUtils {
  /// Wraps a widget in MaterialApp for testing
  static Widget wrapWithApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  /// Pump a widget with app wrapper and wait for animations
  static Future<void> pumpWidget(
    WidgetTester tester,
    Widget widget,
  ) async {
    await tester.pumpWidget(wrapWithApp(widget));
    await tester.pumpAndSettle();
  }

  /// Find a text field by label
  static Finder findTextFieldByLabel(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );
  }

  /// Tap and type into a text field
  static Future<void> enterText(
    WidgetTester tester,
    String text,
  ) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.pumpAndSettle();
  }

  /// Tap a button by text
  static Future<void> tapButton(
    WidgetTester tester,
    String buttonText,
  ) async {
    await tester.tap(find.text(buttonText));
    await tester.pumpAndSettle();
  }

  /// Verify calculator loaded successfully
  static void expectCalculatorLoaded() {
    expect(find.byType(TextField), findsWidgets);
  }

  /// Verify result is displayed
  static void expectResultDisplayed(String result) {
    expect(find.text(result), findsOneWidget);
  }
}

/// Mock data for testing
class TestData {
  static const double homePrice = 300000;
  static const double downPayment = 60000;
  static const double mortgageRate = 6.5;
  static const int mortgageTerm = 30;

  static const double expectedMonthlyPayment = 1520;
}

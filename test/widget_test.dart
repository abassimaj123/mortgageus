import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/main.dart';

void main() {
  testWidgets('App launches and shows MortgageUS', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MortgageUSApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    // Advance past splash timer (1400ms) and fade animation (400ms)
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  });
}

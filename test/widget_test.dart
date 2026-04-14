import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/main.dart';

void main() {
  testWidgets('App launches and shows MortgageUS', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MortgageUSApp()));
    await tester.pump();
    // App loaded if no exception thrown
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Smoke test — vérifie que les widgets de base se construisent sans crash
// N'initialise pas Firebase (incompatible avec l'environnement de test)
void main() {
  group('Smoke — widgets de base', () {
    testWidgets('MaterialApp se construit sans crash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('MortgageUS'))),
        ),
      );
      expect(find.text('MortgageUS'), findsOneWidget);
    });

    testWidgets('NavigationBar se construit sans crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.calculate), label: 'Calculator'),
                NavigationDestination(
                    icon: Icon(Icons.history), label: 'History'),
                NavigationDestination(
                    icon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Calculator'), findsOneWidget);
    });

    testWidgets('TextFormField accepte des inputs numériques', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextFormField(
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '300000');
      expect(find.text('300000'), findsOneWidget);
    });
  });
}

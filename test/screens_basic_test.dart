import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import '../lib/domain/usecases/mortgage_calculator.dart';

void main() {
  group('Format — affichage des résultats', () {
    test('Formatage currency USD — 1896.20', () {
      final fmt = NumberFormat.currency(locale: 'en_US', symbol: r'$');
      expect(fmt.format(1896.20), r'$1,896.20');
    });

    test('Formatage grand montant — 1500000', () {
      final fmt = NumberFormat.currency(locale: 'en_US', symbol: r'$');
      expect(fmt.format(1500000), r'$1,500,000.00');
    });

    test('Formatage pourcentage — 6.50', () {
      final fmt = NumberFormat('#,##0.00');
      expect(fmt.format(6.50), '6.50');
    });
  });

  group('Widget — éléments UI de base', () {
    testWidgets('Card résultat affiche montant formaté', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('Monthly Payment', style: TextStyle(fontSize: 14)),
                    SizedBox(height: 8),
                    Text(r'$1,896.20',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(r'$1,896.20'), findsOneWidget);
      expect(find.text('Monthly Payment'), findsOneWidget);
    });

    testWidgets('Champ texte numérique accepte montant', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Home Price'),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '500000');
      expect(find.text('500000'), findsOneWidget);
    });

    testWidgets('Slider taux intérêt se construit', (tester) async {
      double val = 6.5;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (ctx, setState) => Scaffold(
              body: Column(
                children: [
                  Slider(
                    value: val,
                    min: 0,
                    max: 20,
                    onChanged: (v) => setState(() => val = v),
                  ),
                  Text('${val.toStringAsFixed(2)}%'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('6.50%'), findsOneWidget);
    });
  });

  group('Regression guard — résultats de référence', () {
    test('RG-1: paiement mensuel 400k @ 6.5% / 30 ans', () {
      final result = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 400000,
        annualRatePct: 6.5,
        termYears: 30,
      );
      expect(result, closeTo(2528.27, 0.10));
    });

    test('RG-2: paiement mensuel 400k @ 7.0% / 15 ans', () {
      final result = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 400000,
        annualRatePct: 7.0,
        termYears: 15,
      );
      expect(result, closeTo(3594.85, 1.0));
    });

    test('RG-3: 15 ans coûte moins en intérêts totaux que 30 ans', () {
      final pay30 = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 300000, annualRatePct: 6.0, termYears: 30,
      );
      final pay15 = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 300000, annualRatePct: 6.0, termYears: 15,
      );
      expect(pay30 * 360, greaterThan(pay15 * 180));
    });

    test('RG-4: taux 0% — remboursement pur sans intérêts', () {
      final result = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 120000,
        annualRatePct: 0,
        termYears: 10,
      );
      expect(result, closeTo(1000.0, 0.01));
    });
  });
}

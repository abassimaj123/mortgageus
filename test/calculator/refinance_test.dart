import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

void main() {
  group('calcRefinance', () {

    test('Refi \$250k from 7% to 5.5%: monthly savings ≈ \$347.48', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:          250000,
        currentRatePct:          7.0,
        currentYearsRemaining:   25,
        newRatePct:              5.5,
        newTermYears:            30,
        closingCosts:            5000,
      );
      expect(r.monthlySavings, closeTo(347.48, 1.0));
    });

    test('Refi \$250k from 7% to 5.5%: break-even ≈ 15 months', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:          250000,
        currentRatePct:          7.0,
        currentYearsRemaining:   25,
        newRatePct:              5.5,
        newTermYears:            30,
        closingCosts:            5000,
      );
      expect(r.breakEvenMonths, closeTo(15, 2));
    });

    test('Refi break-even ≤ 84 months → makesSense = true', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:          250000,
        currentRatePct:          7.0,
        currentYearsRemaining:   25,
        newRatePct:              5.5,
        newTermYears:            30,
        closingCosts:            5000,
      );
      expect(r.refinanceMakesSense, isTrue);
    });

    test('Refi to higher rate → negative savings → makesSense = false', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:          250000,
        currentRatePct:          4.0,  // currently low rate
        currentYearsRemaining:   25,
        newRatePct:              7.0,  // worse rate
        newTermYears:            30,
        closingCosts:            5000,
      );
      expect(r.monthlySavings, lessThan(0));
      expect(r.refinanceMakesSense, isFalse);
    });

    test('Refi with very high closing costs → makesSense = false', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:          200000,
        currentRatePct:          6.5,
        currentYearsRemaining:   20,
        newRatePct:              6.0,
        newTermYears:            20,
        closingCosts:            50000, // absurd closing costs
      );
      expect(r.breakEvenMonths, greaterThan(84));
      expect(r.refinanceMakesSense, isFalse);
    });

    test('newMonthlyPayment < oldMonthlyPayment when rate decreases', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:          300000,
        currentRatePct:          7.5,
        currentYearsRemaining:   28,
        newRatePct:              5.5,
        newTermYears:            30,
        closingCosts:            4000,
      );
      expect(r.newMonthlyPayment, lessThan(r.oldMonthlyPayment));
    });

    test('Invalid balance = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcRefinance(
          currentBalance:        0,
          currentRatePct:        7.0,
          currentYearsRemaining: 25,
          newRatePct:            5.5,
          newTermYears:          30,
          closingCosts:          5000,
        ),
        throwsArgumentError,
      );
    });
  });
}

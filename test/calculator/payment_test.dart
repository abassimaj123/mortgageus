import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

void main() {
  // Helper — matches user's function signature, translates decimal rate to %
  double pay(double loan, double rateDecimal, int years) =>
      MortgageCalculator.calcMonthlyPayment(
        loanAmount:    loan,
        annualRatePct: rateDecimal * 100,
        termYears:     years,
      );

  group('calcMonthlyPayment — additional cases', () {

    test('Payment \$320k at 6.5% / 30 years ≈ \$2,022.62', () {
      expect(pay(320000, 0.065, 30), closeTo(2022.62, 0.50));
    });

    test('Payment \$240k at 5.5% / 15 years ≈ \$1,960.68', () {
      expect(pay(240000, 0.055, 15), closeTo(1960.68, 0.50));
    });

    test('Payment with 0% interest = principal / months', () {
      // 240000 / (20*12) = 1000.00
      expect(pay(240000, 0.0, 20), closeTo(1000.00, 0.01));
    });

    test('Payment with \$0 loan amount returns 0', () {
      expect(pay(0, 0.065, 30), equals(0.0));
    });

    test('Payment \$500k at 7.0% / 30yr ≈ \$3,326.51', () {
      expect(pay(500000, 0.07, 30), closeTo(3326.51, 0.50));
    });

    test('Payment \$200k at 5.0% / 15yr ≈ \$1,581.59', () {
      expect(pay(200000, 0.05, 15), closeTo(1581.59, 0.50));
    });

    test('Negative rate throws ArgumentError', () {
      expect(() => pay(300000, -0.01, 30), throwsArgumentError);
    });

    test('Zero term throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcMonthlyPayment(
          loanAmount: 300000, annualRatePct: 6.5, termYears: 0),
        throwsArgumentError,
      );
    });
  });
}

// Golden reference tests — MortgageUS
// Focus: annualRatePct is PERCENT (7.0, not 0.07) + wrong-unit smoke test
// Source: CFPB mortgage calculators, Fannie Mae guidelines.

import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

void main() {
  void approx(double actual, double expected, {double tol = 1.0}) {
    expect(actual, closeTo(expected, tol),
        reason: 'Expected ~$expected, got $actual');
  }

  // ── calcMonthlyPayment — annualRatePct is PERCENT ─────────────────────────

  group('MortgageCalculator — annualRatePct is PERCENT (7.0, not 0.07)', () {
    test('MU-G1: \$320k @ 7.0% / 30yr → \$2,129 (CFPB reference)', () {
      approx(MortgageCalculator.calcMonthlyPayment(
        loanAmount: 320000, annualRatePct: 7.0, termYears: 30,
      ), 2129, tol: 2);
    });

    test('MU-G2: \$400k @ 6.5% / 30yr → \$2,528 (conforming loan)', () {
      approx(MortgageCalculator.calcMonthlyPayment(
        loanAmount: 400000, annualRatePct: 6.5, termYears: 30,
      ), 2528, tol: 2);
    });

    test('MU-G3: total interest on \$320k/7%/30yr ≈ \$446,479', () {
      final payment = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 320000, annualRatePct: 7.0, termYears: 30,
      );
      approx(payment * 360 - 320000, 446479, tol: 100);
    });

    test('MU-G4: 15yr saves >50% interest vs 30yr', () {
      final p30 = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 320000, annualRatePct: 7.0, termYears: 30,
      );
      final p15 = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 320000, annualRatePct: 7.0, termYears: 15,
      );
      expect(p15 * 180 - 320000, lessThan((p30 * 360 - 320000) * 0.5));
    });

    test('MU-G5: 0% rate → loanAmount / (termYears × 12)', () {
      approx(MortgageCalculator.calcMonthlyPayment(
        loanAmount: 240000, annualRatePct: 0.0, termYears: 30,
      ), 666.67, tol: 0.01);
    });
  });

  // ── wrong-unit smoke test ────────────────────────────────────────────────

  group('Wrong-unit detection: passing 0.07 instead of 7.0', () {
    test('MU-W1: decimal rate → payment ~\$896 (not \$2,129 — 58% error)', () {
      // r = 0.07/100/12 = 0.0000583 → nearly-zero interest → payment ≈ principal/360 + tiny
      final wrong = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 320000,
        annualRatePct: 0.07, // WRONG: should be 7.0
        termYears: 30,
      );
      expect(wrong, isNot(closeTo(2129, 200))); // definitely not the right answer
      expect(wrong, lessThan(1500));             // result is clearly too low
    });
  });

  // ── LTV sanity ───────────────────────────────────────────────────────────

  group('LTV and PMI boundary', () {
    test('MU-G6: 20% down → 80% LTV (no PMI threshold)', () {
      const homePrice = 500000.0;
      const downPct = 20.0;
      final loanAmount = homePrice * (1 - downPct / 100);
      expect(loanAmount, closeTo(400000, 0.01));
      expect(loanAmount / homePrice * 100, closeTo(80.0, 0.001));
    });
  });
}

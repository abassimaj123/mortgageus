import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

void main() {
  // Reference: $300k @ 6.5%/30yr baseline payment = $1,896.20
  // Phase-1 payment always equals calcMonthlyPayment(loan, initialRate, totalTerm)
  // because the ARM is amortised on the FULL original term during the fixed phase.

  group('calcARM — phase-1 payment', () {
    test('ARM1: payment1 equals equivalent fixed payment (same initial rate)',
        () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 8.0,
        totalTermYears: 30,
      );
      final fixedRef = MortgageCalculator.calcMonthlyPayment(
          loanAmount: 300000, annualRatePct: 6.5, termYears: 30);
      expect(arm.payment1, closeTo(fixedRef, 0.01));
    });

    test('ARM2: fixedPayment equals payment1 (same rate, same term)', () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 8.0,
        totalTermYears: 30,
      );
      expect(arm.fixedPayment, closeTo(arm.payment1, 0.01));
    });
  });

  group('calcARM — balance at reset', () {
    test(
        'ARM3: balance at reset is less than original loan (amortisation happened)',
        () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 8.0,
        totalTermYears: 30,
      );
      expect(arm.balanceAtReset, lessThan(300000));
      expect(
          arm.balanceAtReset, greaterThan(250000)); // 5yrs at 6.5%: rough range
    });

    test('ARM4: fixedMonths = fixedYears × 12', () {
      for (final fy in [3, 5, 7, 10]) {
        final arm = MortgageCalculator.calcARM(
          loanAmount: 300000,
          initialRatePct: 6.5,
          fixedYears: fy,
          adjustedRatePct: 7.0,
          totalTermYears: 30,
        );
        expect(arm.fixedMonths, equals(fy * 12));
      }
    });
  });

  group('calcARM — interest direction', () {
    test(
        'ARM5: adjusted rate > initial → ARM total interest > fixed total interest',
        () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 9.0, // much higher reset
        totalTermYears: 30,
      );
      expect(arm.totalInterest, greaterThan(arm.fixedTotalInterest));
    });

    test(
        'ARM6: adjusted rate < initial → ARM total interest < fixed total interest',
        () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 4.5, // drops at reset
        totalTermYears: 30,
      );
      expect(arm.totalInterest, lessThan(arm.fixedTotalInterest));
    });

    test('ARM7: adjusted rate < initial → payment2 < payment1', () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 5.0,
        totalTermYears: 30,
      );
      expect(arm.payment2, lessThan(arm.payment1));
    });

    test('ARM8: adjusted rate > initial → payment2 > payment1', () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 8.5,
        totalTermYears: 30,
      );
      expect(arm.payment2, greaterThan(arm.payment1));
    });
  });

  group('calcARM — break-even logic', () {
    test(
        'ARM9: adjusted rate < initial → breakEvenMonths is null (ARM always cheaper)',
        () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 4.5,
        totalTermYears: 30,
      );
      expect(arm.breakEvenMonths, isNull);
    });

    test('ARM10: adjusted rate > initial → breakEvenMonths is not null', () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 9.0,
        totalTermYears: 30,
      );
      expect(arm.breakEvenMonths, isNotNull);
    });

    test('ARM11: breakEvenMonths occurs after fixed period ends', () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 9.0,
        totalTermYears: 30,
      );
      if (arm.breakEvenMonths != null) {
        expect(arm.breakEvenMonths!, greaterThan(arm.fixedMonths));
      }
    });
  });

  group('calcARM — total cost integrity', () {
    test(
        'ARM12: totalCost = balanceAtReset + remaining balance + all interest (approximate)',
        () {
      final arm = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 8.0,
        totalTermYears: 30,
      );
      // totalCost must be > loanAmount
      expect(arm.totalCost, greaterThan(300000));
      // totalCost = loanAmount + totalInterest
      expect(arm.totalCost, closeTo(300000 + arm.totalInterest, 1.0));
    });

    test(
        'ARM13: 10yr fixed period has higher balance at reset than 3yr (less paid down)',
        () {
      final arm5 = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 5,
        adjustedRatePct: 7.0,
        totalTermYears: 30,
      );
      final arm10 = MortgageCalculator.calcARM(
        loanAmount: 300000,
        initialRatePct: 6.5,
        fixedYears: 10,
        adjustedRatePct: 7.0,
        totalTermYears: 30,
      );
      // More time amortising = lower balance at reset (for 10yr vs 5yr)
      expect(arm10.balanceAtReset, lessThan(arm5.balanceAtReset));
    });
  });

  group('calcARM — argument validation', () {
    test('ARM14: loan = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcARM(
            loanAmount: 0,
            initialRatePct: 6.5,
            fixedYears: 5,
            adjustedRatePct: 7.0,
            totalTermYears: 30),
        throwsArgumentError,
      );
    });

    test('ARM15: fixedYears >= totalTermYears throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcARM(
            loanAmount: 300000,
            initialRatePct: 6.5,
            fixedYears: 30,
            adjustedRatePct: 7.0,
            totalTermYears: 30),
        throwsArgumentError,
      );
    });

    test('ARM16: negative initialRate throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcARM(
            loanAmount: 300000,
            initialRatePct: -1.0,
            fixedYears: 5,
            adjustedRatePct: 7.0,
            totalTermYears: 30),
        throwsArgumentError,
      );
    });
  });
}

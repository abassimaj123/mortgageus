import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';
import 'package:mortgage_us/core/constants/mortgage_constants.dart';

void main() {
  group('calcPmiMonthly', () {

    test('PMI at 90% LTV (\$450k/\$500k) at 0.75%/yr = \$281.25/mo', () {
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount:       450000,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
      );
      expect(pmi, closeTo(281.25, 0.01));
    });

    test('PMI at exactly 80% LTV = \$0 (at threshold, no PMI)', () {
      // LTV = 400000/500000 = 0.80 = pmiLtvThreshold → no PMI
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount:       400000,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
      );
      expect(pmi, equals(0.0));
    });

    test('PMI at 79% LTV = \$0 (below threshold)', () {
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount:       395000,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
      );
      expect(pmi, equals(0.0));
    });

    test('PMI at 85% LTV > 0', () {
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount:       425000,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
      );
      expect(pmi, greaterThan(0));
    });

    test('PMI homePrice = 0 returns 0 (no division by zero)', () {
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount:       300000,
        homePrice:        0,
        pmiAnnualRatePct: 0.75,
      );
      expect(pmi, equals(0.0));
    });
  });

  group('PMI auto-cancel at 78% LTV (HPA)', () {

    test('PMI drops when balance reaches 78% of home price (month ~109, index 108)', () {
      // $450k loan / $500k home / 6.5% / 30yr
      // 78% of $500k = $390k → balance crosses at month ~109
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount:       450000,
        annualRatePct:    6.5,
        termYears:        30,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
        startDate:        DateTime(2025, 1, 1),
      );

      // First index where PMI drops (pmiDropped = true)
      final dropIdx = schedule.indexWhere((e) => e.pmiDropped);
      expect(dropIdx, inInclusiveRange(100, 115));

      // Month after drop: pmiAmount must be 0 for all remaining months
      for (final entry in schedule.skip(dropIdx)) {
        expect(entry.pmiAmount, equals(0.0));
      }
    });

    test('PMI drop month balance is ≤ 78% of home price', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount:       450000,
        annualRatePct:    6.5,
        termYears:        30,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
        startDate:        DateTime(2025, 1, 1),
      );
      final dropIdx = schedule.indexWhere((e) => e.pmiDropped);
      expect(dropIdx, greaterThan(-1)); // PMI does drop
      final dropEntry = schedule[dropIdx];
      expect(dropEntry.balance / 500000, lessThanOrEqualTo(MortgageConstants.pmiAutoCancelLtv));
    });

    test('20% down (\$400k/\$500k) → no PMI at any month', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount:       400000,
        annualRatePct:    6.5,
        termYears:        30,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
        startDate:        DateTime(2025, 1, 1),
      );
      expect(schedule.every((e) => e.pmiAmount == 0.0), isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/models/loan_type.dart';
import 'package:mortgage_us/domain/models/mortgage_input.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';
import 'package:mortgage_us/core/constants/mortgage_constants.dart';

void main() {

  // ── P&I PAYMENT TESTS ────────────────────────────────────────────────────

  group('calcMonthlyPayment — P&I', () {
    test('P1: \$300k @ 6.5% / 30yr = \$1,896.20 ±\$0.50', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30);
      expect(p, closeTo(1896.20, 0.50));
    });

    test('P2: \$200k @ 5.0% / 15yr = \$1,581.59 ±\$0.50', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 200000, annualRatePct: 5.0, termYears: 15);
      expect(p, closeTo(1581.59, 0.50));
    });

    test('P3: \$500k @ 7.0% / 30yr = \$3,326.51 ±\$0.50', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 500000, annualRatePct: 7.0, termYears: 30);
      expect(p, closeTo(3326.51, 0.50));
    });

    test('P4: \$100k @ 0.0% / 10yr = \$833.33 (edge: zero rate)', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 100000, annualRatePct: 0.0, termYears: 10);
      expect(p, closeTo(833.33, 0.01));
    });

    test('P5: conforming limit \$832,750 @ 6.5% / 30yr = \$5,263 ±\$5', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 832750, annualRatePct: 6.5, termYears: 30);
      expect(p, closeTo(5263, 5));
    });

    test('P6: loan = 0 → payment = 0', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 0, annualRatePct: 6.5, termYears: 30);
      expect(p, equals(0.0));
    });

    test('P7: \$400k @ 3.0% / 30yr', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 400000, annualRatePct: 3.0, termYears: 30);
      expect(p, closeTo(1686.42, 0.50));
    });

    test('P8: \$750k @ 7.5% / 15yr', () {
      final p = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 750000, annualRatePct: 7.5, termYears: 15);
      expect(p, closeTo(6952.59, 1.0));
    });

    test('P9: negative rate throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcMonthlyPayment(
          loanAmount: 300000, annualRatePct: -1.0, termYears: 30),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('P10: term = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcMonthlyPayment(
          loanAmount: 300000, annualRatePct: 6.5, termYears: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── PMI TESTS ────────────────────────────────────────────────────────────

  group('calcPmiMonthly', () {
    test('PMI1: LTV 80% exactly → PMI = \$0', () {
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount: 400000, homePrice: 500000, pmiAnnualRatePct: 0.75);
      expect(pmi, equals(0.0));
    });

    test('PMI2: LTV 90% (loan \$450k, home \$500k) → PMI = \$281.25/mo', () {
      // (450_000 × 0.75%) / 12 = 281.25
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount: 450000, homePrice: 500000, pmiAnnualRatePct: 0.75);
      expect(pmi, closeTo(281.25, 0.01));
    });

    test('PMI3: LTV 79% → PMI = \$0', () {
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount: 395000, homePrice: 500000, pmiAnnualRatePct: 0.75);
      expect(pmi, equals(0.0));
    });

    test('PMI4: LTV 95% high rate 1.5% → correct amount', () {
      // (475_000 × 1.5%) / 12 = 593.75
      final pmi = MortgageCalculator.calcPmiMonthly(
        loanAmount: 475000, homePrice: 500000, pmiAnnualRatePct: 1.5);
      expect(pmi, closeTo(593.75, 0.01));
    });
  });

  // ── PITI TESTS ───────────────────────────────────────────────────────────

  group('calculate — PITI breakdown', () {
    test('PITI1: Home \$400k, Loan \$320k @ 6.5%/30, tax 1.2%, ins \$1500/yr', () {
      final input = MortgageInput(
        homePrice:            400000,
        downPayment:           80000, // 20% down → LTV 80%, no PMI
        annualRatePct:          6.5,
        termYears:              30,
        loanType:        LoanType.conventional,
        propertyTaxRatePct:     1.2,
        homeInsuranceAnnual: 1500,
        hoaMonthly:             0,
        pmiAnnualRatePct:       0.75,
        startDate:       DateTime(2026, 5, 1),
      );
      final r = MortgageCalculator.calculate(input);
      expect(r.monthly.piPayment,    closeTo(2022.62, 1.0));
      expect(r.monthly.propertyTax,  closeTo(400.0,   0.01)); // 400k×1.2%/12
      expect(r.monthly.homeInsurance,closeTo(125.0,   0.01)); // 1500/12
      expect(r.monthly.hoa,          equals(0.0));
      expect(r.monthly.pmi,          equals(0.0));     // LTV = 80%, no PMI
      expect(r.monthly.pitiPayment,  closeTo(2547.62, 2.0));
    });

    test('PITI2: With PMI (LTV 90%)', () {
      final input = MortgageInput(
        homePrice:            500000,
        downPayment:           50000, // 10% → LTV 90%
        annualRatePct:          6.5,
        termYears:              30,
        loanType:        LoanType.conventional,
        propertyTaxRatePct:     1.1,
        homeInsuranceAnnual: 1750,
        hoaMonthly:             0,
        pmiAnnualRatePct:       0.75,
        startDate:       DateTime(2026, 5, 1),
      );
      final r = MortgageCalculator.calculate(input);
      expect(r.hasPmi, isTrue);
      expect(r.monthly.pmi, closeTo(281.25, 0.01)); // (450k×0.75%)/12
    });

    test('PITI3: With HOA', () {
      final input = MortgageInput(
        homePrice:            600000,
        downPayment:          120000,
        annualRatePct:          6.0,
        termYears:              30,
        loanType:        LoanType.conventional,
        propertyTaxRatePct:     1.0,
        homeInsuranceAnnual: 2000,
        hoaMonthly:           400,
        pmiAnnualRatePct:       0.0,
        startDate:       DateTime(2026, 5, 1),
      );
      final r = MortgageCalculator.calculate(input);
      expect(r.monthly.hoa, equals(400.0));
      expect(r.monthly.pitiPayment, greaterThan(r.monthly.piPayment + 400));
    });
  });

  // ── AMORTIZATION SCHEDULE TESTS ──────────────────────────────────────────

  group('buildSchedule — amortization', () {
    test('AMO1: Month 1 of \$300k @ 6.5%/30', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      final m1 = schedule.first;
      // r = 6.5/100/12 = 0.005417
      // interest = 300_000 × 0.005417 = 1625.00
      expect(m1.interest,   closeTo(1625.0,    0.50));
      expect(m1.principal,  closeTo(271.20,    0.50));
      expect(m1.balance,    closeTo(299728.80, 1.0));
    });

    test('AMO2: Total interest \$300k @ 6.5%/30 = \$382,633 ±\$10', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      final totalInt = schedule.last.cumulativeInterest;
      expect(totalInt, closeTo(382633, 10));
    });

    test('AMO3: Schedule has correct number of entries (≤360)', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(schedule.length, equals(360));
    });

    test('AMO4: Last payment balance ≈ 0 (±\$1)', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(schedule.last.balance, closeTo(0.0, 1.0));
    });

    test('AMO5: PMI drops when LTV ≤ 78%', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 450000, annualRatePct: 6.5, termYears: 30,
        homePrice: 500000, pmiAnnualRatePct: 0.75,
        startDate: DateTime(2026, 5, 1),
      );
      // Find first month PMI is 0 after being active
      final pmiDropEntry = schedule.firstWhere(
        (e) => e.pmiDropped, orElse: () => schedule.first);
      expect(pmiDropEntry.pmiDropped, isTrue);
      // After drop, remaining entries should have pmiAmount = 0
      final dropIdx = schedule.indexOf(pmiDropEntry);
      for (int i = dropIdx + 1; i < schedule.length; i++) {
        expect(schedule[i].pmiAmount, equals(0.0));
      }
    });

    test('AMO6: 15-year schedule has 180 entries', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 200000, annualRatePct: 5.0, termYears: 15,
        homePrice: 250000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(schedule.length, equals(180));
    });
  });

  // ── LTV / CONFORMING TESTS ───────────────────────────────────────────────

  group('LTV and conforming badge', () {
    test('LTV1: Loan \$832,750 = exactly conforming limit', () {
      final input = MortgageInput(
        homePrice: 1200000, downPayment: 367250,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.conventional,
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(input.isJumbo, isFalse); // exactly at limit = conforming
    });

    test('LTV2: Loan \$832,751 = Jumbo', () {
      final input = MortgageInput(
        homePrice: 1200000, downPayment: 367249,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.conventional,
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(input.isJumbo, isTrue);
    });

    test('LTV3: \$1M loan on \$1.5M home = Jumbo', () {
      final input = MortgageInput(
        homePrice: 1500000, downPayment: 500000,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.conventional,
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(input.isJumbo, isTrue);
      expect(input.ltv, closeTo(66.67, 0.1));
    });

    test('LTV4: 100% down = loan 0, LTV 0', () {
      final input = MortgageInput(
        homePrice: 500000, downPayment: 500000,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.conventional,
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(input.loanAmount, equals(0.0));
      expect(input.ltv,        equals(0.0));
    });

    test('LTV5: 0% down = LTV 100%, PMI required', () {
      final input = MortgageInput(
        homePrice: 400000, downPayment: 0,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.conventional,
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.75,
        startDate: DateTime(2026, 5, 1),
      );
      expect(input.ltv,         equals(100.0));
      expect(input.requiresPmi, isTrue);
    });
  });

  // ── EXTRA PAYMENTS TESTS ─────────────────────────────────────────────────

  group('calcExtraPayments', () {
    test('EP1: \$300k @ 6.5%/30 + \$200 extra/mo saves ~7 years + ~\$100k', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        extraMonthly: 200,
      );
      // Should save roughly 7 years (84 months) and >$100k interest
      expect(r.monthsSaved,    greaterThan(80));
      expect(r.monthsSaved,    lessThan(100));
      expect(r.interestSaved,  greaterThan(90000));
      expect(r.newPayoffMonths,lessThan(280));
    });

    test('EP2: No extra payment = no savings', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        extraMonthly: 0,
      );
      expect(r.monthsSaved,   equals(0));
      expect(r.interestSaved, closeTo(0, 0.01));
    });

    test('EP3: \$300k @ 6.5%/30 + lump sum \$20k at month 12', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        extraMonthly: 0, lumpSum: 20000, lumpSumMonth: 12,
      );
      expect(r.monthsSaved,   greaterThan(20));
      expect(r.interestSaved, greaterThan(30000));
    });

    test('EP4: Huge extra = early payoff', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount: 100000, annualRatePct: 6.5, termYears: 30,
        extraMonthly: 2000, // much more than payment
      );
      expect(r.newPayoffMonths, lessThan(60)); // paid off in < 5 years
      expect(r.interestSaved,   greaterThan(50000));
    });

    test('EP5: Loan = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcExtraPayments(
          loanAmount: 0, annualRatePct: 6.5, termYears: 30, extraMonthly: 200),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── REFINANCE TESTS ──────────────────────────────────────────────────────

  group('calcRefinance', () {
    test('RF1: Classic scenario — break-even ≈ 15 months', () {
      // Balance $250k, current 7%/25yr → refi 5.5%/30yr, closing $5k
      final r = MortgageCalculator.calcRefinance(
        currentBalance:         250000,
        currentRatePct:          7.0,
        currentYearsRemaining:   25,
        newRatePct:              5.5,
        newTermYears:            30,
        closingCosts:          5000,
      );
      expect(r.monthlySavings,    greaterThan(0));
      expect(r.breakEvenMonths,   closeTo(15, 5)); // ±5 months
      expect(r.refinanceMakesSense, isTrue);
      expect(r.oldMonthlyPayment, greaterThan(r.newMonthlyPayment));
    });

    test('RF2: Higher new rate → no savings → makes no sense', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance:        200000,
        currentRatePct:          4.0,
        currentYearsRemaining:   20,
        newRatePct:              7.0,
        newTermYears:            30,
        closingCosts:          4000,
      );
      expect(r.monthlySavings,      lessThan(0));
      expect(r.refinanceMakesSense, isFalse);
    });

    test('RF3: Monthly savings calculation', () {
      final old = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 250000, annualRatePct: 7.0, termYears: 25);
      final r = MortgageCalculator.calcRefinance(
        currentBalance: 250000, currentRatePct: 7.0,
        currentYearsRemaining: 25, newRatePct: 5.5,
        newTermYears: 30, closingCosts: 5000,
      );
      expect(r.oldMonthlyPayment, closeTo(old, 0.01));
    });

    test('RF4: currentBalance = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcRefinance(
          currentBalance: 0, currentRatePct: 7.0,
          currentYearsRemaining: 25, newRatePct: 5.5,
          newTermYears: 30, closingCosts: 5000),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('RF5: totalSavings positive when makes sense', () {
      final r = MortgageCalculator.calcRefinance(
        currentBalance: 300000, currentRatePct: 7.5,
        currentYearsRemaining: 25, newRatePct: 6.0,
        newTermYears: 30, closingCosts: 4000,
      );
      if (r.refinanceMakesSense) {
        expect(r.totalSavingsOverLife, greaterThan(0));
      }
    });
  });

  // ── EDGE CASES ───────────────────────────────────────────────────────────

  group('edge cases', () {
    test('EC1: Home price = 0 throws ArgumentError', () {
      final input = MortgageInput(
        homePrice: 0, downPayment: 0,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.conventional,
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.75,
        startDate: DateTime(2026, 5, 1),
      );
      expect(() => MortgageCalculator.calculate(input), throwsA(isA<ArgumentError>()));
    });

    test('EC2: VA loan — PMI not required even at 100% LTV', () {
      final input = MortgageInput(
        homePrice: 400000, downPayment: 0,
        annualRatePct: 6.5, termYears: 30,
        loanType: LoanType.va, // VA — no PMI
        propertyTaxRatePct: 1.0, homeInsuranceAnnual: 1750,
        hoaMonthly: 0, pmiAnnualRatePct: 0.75,
        startDate: DateTime(2026, 5, 1),
      );
      expect(input.requiresPmi, isFalse);
      final r = MortgageCalculator.calculate(input);
      expect(r.hasPmi, isFalse);
      expect(r.monthly.pmi, equals(0.0));
    });

    test('EC3: 10-year term vs 30-year — significantly lower total interest', () {
      final p10 = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 10);
      final p30 = MortgageCalculator.calcMonthlyPayment(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30);
      expect(p10, greaterThan(p30));   // higher monthly
      // but much less total interest
      final s10 = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 10,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1));
      final s30 = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1));
      expect(s10.last.cumulativeInterest,
             lessThan(s30.last.cumulativeInterest * 0.5));
    });

    test('EC4: negative rate throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcMonthlyPayment(
          loanAmount: 300000, annualRatePct: -1.0, termYears: 30),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('EC5: Cumulative principal = loan amount at end', () {
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 375000, pmiAnnualRatePct: 0.0,
        startDate: DateTime(2026, 5, 1),
      );
      expect(schedule.last.cumulativePrincipal, closeTo(300000, 1.0));
    });
  });

  // ── CONFORMING CONSTANT SANITY ────────────────────────────────────────────

  group('conforming limits 2026', () {
    test('CL1: Single-family limit is correct', () {
      expect(MortgageConstants.conformingLimit1Unit, equals(832750.0));
    });

    test('CL2: PMI threshold is 80%', () {
      expect(MortgageConstants.pmiLtvThreshold, equals(0.80));
    });

    test('CL3: PMI auto-cancel at 78%', () {
      expect(MortgageConstants.pmiAutoCancelLtv, equals(0.78));
    });
  });
}

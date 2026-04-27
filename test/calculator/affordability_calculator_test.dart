import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

// Reference scenario A:
//   annualIncome=$100k, monthlyDebts=$0, downPayment=$60k,
//   rate=6.5%, term=30yr, tax=1.1%, ins=$1750, hoa=$0
//
//   monthlyGross = 8,333.33
//   maxPITI_conservative (28%) = 2,333.33
//   maxPITI_standard (43%)     = 3,583.33  (no debts)

void main() {

  // ── Income / monthly breakdown ────────────────────────────────────────────

  group('calcAffordability — monthly gross income', () {

    test('AF1: monthlyGrossIncome = annualIncome / 12', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 120000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.monthlyGrossIncome, closeTo(10000.0, 0.01));
    });

    test('AF2: inputDownPayment matches the parameter', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  75000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.inputDownPayment, equals(75000.0));
    });
  });

  // ── Max home price ordering ───────────────────────────────────────────────

  group('calcAffordability — price ordering', () {

    test('AF3: standard >= conservative when monthly debts = 0', () {
      // With $0 debts: back-end 43% ≥ front-end 28% always
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.maxHomePriceStandard, greaterThanOrEqualTo(r.maxHomePriceConservative));
    });

    test('AF4: both prices > 0 for valid income', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 500,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.maxHomePriceConservative, greaterThan(0));
      expect(r.maxHomePriceStandard,     greaterThan(0));
    });

    test(r'AF5: conservative ≈ $330,000 ±$10,000 for reference scenario', () {
      // $100k income, $0 debts, $60k down, 6.5%, 30yr
      // 28% of monthly gross = $2,333 → home price ≈ $330k
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.maxHomePriceConservative, closeTo(330000, 10000));
    });

    test(r'AF6: standard ≈ $490,000 ±$15,000 for reference scenario (no debts)', () {
      // 43% of monthly gross = $3,583 → home price ≈ $490k
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.maxHomePriceStandard, closeTo(490000, 15000));
    });
  });

  // ── Effect of debts ───────────────────────────────────────────────────────

  group('calcAffordability — monthly debts impact', () {

    test('AF7: higher monthly debts → lower standard home price', () {
      final low = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      final high = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 1500,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(high.maxHomePriceStandard, lessThan(low.maxHomePriceStandard));
    });

    test('AF8: debts do NOT affect conservative price (28% front-end DTI is PITI only)', () {
      final noDbt = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      final withDbt = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 1000,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      // Conservative only uses 28% front-end (no debts in formula)
      expect(noDbt.maxHomePriceConservative,
             closeTo(withDbt.maxHomePriceConservative, 10));
    });
  });

  // ── Monthly breakdown integrity ───────────────────────────────────────────

  group('calcAffordability — monthly breakdown', () {

    test('AF9: totalMonthly = PI + tax + insurance + PMI + HOA', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
        propertyTaxRatePct:  1.1,
        homeInsuranceAnnual: 1750,
        hoaMonthly: 0,
      );
      final sum = r.monthlyPI + r.monthlyTax + r.monthlyInsurance
                + r.monthlyPMI + r.monthlyHOA;
      expect(r.totalMonthly, closeTo(sum, 0.01));
    });

    test('AF10: monthlyInsurance = homeInsuranceAnnual / 12', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
        homeInsuranceAnnual: 2400,
      );
      expect(r.monthlyInsurance, closeTo(200.0, 0.01));
    });

    test('AF11: HOA passed through correctly', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
        hoaMonthly: 300,
      );
      expect(r.monthlyHOA, equals(300.0));
    });
  });

  // ── Max loan ordering ─────────────────────────────────────────────────────

  group('calcAffordability — loan amounts', () {

    test('AF12: maxLoanStandard ≈ maxHomePriceStandard - downPayment', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.maxLoanStandard,
             closeTo(r.maxHomePriceStandard - 60000, 1.0));
    });

    test('AF13: maxLoanConservative ≈ maxHomePriceConservative - downPayment', () {
      final r = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      expect(r.maxLoanConservative,
             closeTo(r.maxHomePriceConservative - 60000, 1.0));
    });
  });

  // ── Higher income → higher ceiling ───────────────────────────────────────

  group('calcAffordability — income scaling', () {

    test('AF14: doubling income approximately doubles max home price', () {
      final r1 = MortgageCalculator.calcAffordability(
        annualIncome: 80000, monthlyDebts: 0,
        downPayment:  50000, annualRatePct: 6.5, termYears: 30,
      );
      final r2 = MortgageCalculator.calcAffordability(
        annualIncome: 160000, monthlyDebts: 0,
        downPayment:  50000, annualRatePct: 6.5, termYears: 30,
      );
      // Standard price should roughly scale with income (not exact due to
      // non-linearity from fixed insurance/down, but should be clearly larger)
      expect(r2.maxHomePriceStandard,
             greaterThan(r1.maxHomePriceStandard * 1.6));
    });

    test('AF15: 15yr term → lower max home price than 30yr (higher monthly P&I)', () {
      final r30 = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 30,
      );
      final r15 = MortgageCalculator.calcAffordability(
        annualIncome: 100000, monthlyDebts: 0,
        downPayment:  60000, annualRatePct: 6.5, termYears: 15,
      );
      // 15yr payment is higher → less room for home price under same DTI
      expect(r15.maxHomePriceStandard, lessThan(r30.maxHomePriceStandard));
    });
  });

  // ── Error handling ────────────────────────────────────────────────────────

  group('calcAffordability — argument validation', () {

    test('AF16: annualIncome = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcAffordability(
          annualIncome: 0, monthlyDebts: 0,
          downPayment: 60000, annualRatePct: 6.5, termYears: 30,
        ),
        throwsArgumentError,
      );
    });

    test('AF17: termYears = 0 throws ArgumentError', () {
      expect(
        () => MortgageCalculator.calcAffordability(
          annualIncome: 100000, monthlyDebts: 0,
          downPayment: 60000, annualRatePct: 6.5, termYears: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

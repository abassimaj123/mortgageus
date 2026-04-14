import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/core/constants/mortgage_constants.dart';
import 'package:mortgage_us/domain/models/loan_type.dart';
import 'package:mortgage_us/domain/models/mortgage_input.dart';

// Helper — builds minimal MortgageInput with a given loan amount
MortgageInput _input(double homePrice, double downPayment) => MortgageInput(
  homePrice:            homePrice,
  downPayment:          downPayment,
  annualRatePct:        6.5,
  termYears:            30,
  loanType:             LoanType.conventional,
  propertyTaxRatePct:   1.1,
  homeInsuranceAnnual:  1750,
  hoaMonthly:           0,
  pmiAnnualRatePct:     0.75,
  startDate:            DateTime(2025, 1, 1),
);

void main() {
  group('Conforming loan limits 2026 (FHFA)', () {

    test('Conforming limit 1-unit = \$832,750', () {
      expect(MortgageConstants.conformingLimit1Unit, equals(832750.0));
    });

    test('Loan at \$832,750 is NOT jumbo (conforming)', () {
      // homePrice $1M, down $167,250 → loan $832,750
      final inp = _input(1000000, 167250);
      expect(inp.loanAmount, closeTo(832750, 0.01));
      expect(inp.isJumbo, isFalse);
    });

    test('Loan at \$832,751 IS jumbo', () {
      // homePrice $1M, down $167,249 → loan $832,751
      final inp = _input(1000000, 167249);
      expect(inp.loanAmount, closeTo(832751, 0.01));
      expect(inp.isJumbo, isTrue);
    });

    test('Loan at \$1,000,000 IS jumbo', () {
      final inp = _input(1200000, 200000); // loan $1M
      expect(inp.isJumbo, isTrue);
    });

    test('Loan at \$500,000 is NOT jumbo', () {
      final inp = _input(625000, 125000); // 20% down → loan $500k
      expect(inp.isJumbo, isFalse);
    });
  });

  group('High-cost area limit (FHFA 2026)', () {

    test('High-cost conforming limit = \$1,249,125', () {
      expect(MortgageConstants.conformingLimitHighCost, equals(1249125.0));
    });

    test('Loan at \$1,249,125 is within high-cost conforming limit', () {
      expect(1249125.0, lessThanOrEqualTo(MortgageConstants.conformingLimitHighCost));
    });

    test('Loan at \$1,249,126 exceeds high-cost conforming limit', () {
      expect(1249126.0, greaterThan(MortgageConstants.conformingLimitHighCost));
    });
  });

  group('VA loan — no PMI regardless of LTV', () {

    test('VA loan requiresPmi = false even at 95% LTV', () {
      final va = MortgageInput(
        homePrice:            500000,
        downPayment:          25000, // 5% down → 95% LTV
        annualRatePct:        6.5,
        termYears:            30,
        loanType:             LoanType.va,
        propertyTaxRatePct:   1.1,
        homeInsuranceAnnual:  1750,
        hoaMonthly:           0,
        pmiAnnualRatePct:     0.75,
        startDate:            DateTime(2025, 1, 1),
      );
      expect(va.ltv, greaterThan(80.0));
      expect(va.requiresPmi, isFalse); // VA: never PMI
    });
  });
}

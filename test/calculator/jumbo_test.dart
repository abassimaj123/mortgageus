import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/core/constants/mortgage_constants.dart';
import 'package:mortgage_us/domain/models/loan_type.dart';
import 'package:mortgage_us/domain/models/mortgage_input.dart';

// Helper — builds minimal MortgageInput with a given loan amount
MortgageInput _input(double homePrice, double downPayment) => MortgageInput(
      homePrice: homePrice,
      downPayment: downPayment,
      annualRatePct: 6.5,
      termYears: 30,
      loanType: LoanType.conventional,
      propertyTaxRatePct: 1.1,
      homeInsuranceAnnual: 1750,
      hoaMonthly: 0,
      pmiAnnualRatePct: 0.75,
      startDate: DateTime(2025, 1, 1),
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
      expect(1249125.0,
          lessThanOrEqualTo(MortgageConstants.conformingLimitHighCost));
    });

    test('Loan at \$1,249,126 exceeds high-cost conforming limit', () {
      expect(1249126.0, greaterThan(MortgageConstants.conformingLimitHighCost));
    });
  });

  // Guardrail: these now source from the CalcwiseTax registry (verified 2026).
  // Pin exact figures and assert DECIMAL units to catch percent-vs-decimal bugs.
  group('Registry-sourced limits & rates (decimal units)', () {
    test('Conforming baseline = \$832,750 (registry)', () {
      expect(MortgageConstants.conformingLimit1Unit, equals(832750.0));
    });

    test('Conforming ceiling = \$1,249,125 (registry)', () {
      expect(MortgageConstants.conformingLimitHighCost, equals(1249125.0));
    });

    test('FHA floor = \$541,287 / ceiling = \$1,249,125 (registry)', () {
      expect(MortgageConstants.fhaFloor, equals(541287.0));
      expect(MortgageConstants.fhaCeiling, equals(1249125.0));
    });

    test('FHA annual MIP high-LTV = 0.0055 (0.55%, decimal)', () {
      expect(MortgageConstants.fhaAnnualMip, equals(0.0055));
      expect(MortgageConstants.fhaAnnualMip, lessThan(0.1)); // decimal, not %
    });

    test('FHA annual MIP low-LTV = 0.005 (0.50%, decimal)', () {
      expect(MortgageConstants.fhaAnnualMipLowLtv, equals(0.005));
    });

    test('FHA upfront MIP = 0.0175 (1.75%, decimal)', () {
      expect(MortgageConstants.fhaUpfrontMip, equals(0.0175));
    });

    test('VA funding fee first-use, <5% down = 0.0215 (2.15%, decimal)', () {
      expect(MortgageConstants.vaFundingFeeFirst, equals(0.0215));
      expect(MortgageConstants.vaFundingFeeFirst, lessThan(0.1));
    });

    test('VA funding fee subsequent-use = 0.033 (3.3%, decimal)', () {
      expect(MortgageConstants.vaFundingFeeSubsequent, equals(0.033));
    });

    test('PMI applies above 0.80 LTV (decimal)', () {
      expect(MortgageConstants.pmiLtvThreshold, equals(0.80));
    });
  });

  group('VA loan — no PMI regardless of LTV', () {
    test('VA loan requiresPmi = false even at 95% LTV', () {
      final va = MortgageInput(
        homePrice: 500000,
        downPayment: 25000, // 5% down → 95% LTV
        annualRatePct: 6.5,
        termYears: 30,
        loanType: LoanType.va,
        propertyTaxRatePct: 1.1,
        homeInsuranceAnnual: 1750,
        hoaMonthly: 0,
        pmiAnnualRatePct: 0.75,
        startDate: DateTime(2025, 1, 1),
      );
      expect(va.ltv, greaterThan(80.0));
      expect(va.requiresPmi, isFalse); // VA: never PMI
    });
  });
}

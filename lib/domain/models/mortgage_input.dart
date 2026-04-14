import 'loan_type.dart';

class MortgageInput {
  final double homePrice;
  final double downPayment;        // absolute $
  final double annualRatePct;      // e.g. 6.5 for 6.5%
  final int    termYears;
  final LoanType loanType;
  final double propertyTaxRatePct; // annual % of home value
  final double homeInsuranceAnnual; // $/year
  final double hoaMonthly;
  final double pmiAnnualRatePct;   // 0 = no PMI, 0.75 = 0.75%
  final DateTime startDate;

  const MortgageInput({
    required this.homePrice,
    required this.downPayment,
    required this.annualRatePct,
    required this.termYears,
    required this.loanType,
    required this.propertyTaxRatePct,
    required this.homeInsuranceAnnual,
    required this.hoaMonthly,
    required this.pmiAnnualRatePct,
    required this.startDate,
  });

  double get loanAmount     => homePrice - downPayment;
  double get downPaymentPct => homePrice > 0 ? (downPayment / homePrice) * 100 : 0;
  double get ltv            => homePrice > 0 ? (loanAmount / homePrice) * 100 : 0;

  bool get isJumbo     => loanAmount > 832750.0;
  bool get requiresPmi => ltv > 80.0 && loanType != LoanType.va;
}

import 'amortization_entry.dart';

class MonthlyBreakdown {
  final double principal;
  final double interest;
  final double propertyTax;
  final double homeInsurance;
  final double hoa;
  final double pmi;

  const MonthlyBreakdown({
    required this.principal,
    required this.interest,
    required this.propertyTax,
    required this.homeInsurance,
    required this.hoa,
    required this.pmi,
  });

  double get piPayment   => principal + interest;
  double get pitiPayment => principal + interest + propertyTax + homeInsurance + hoa + pmi;
}

class MortgageResult {
  final double             loanAmount;
  final MonthlyBreakdown   monthly;
  final double             totalInterest;
  final double             totalCost;
  final DateTime           payoffDate;
  final double             currentLtv;
  final bool               isJumbo;
  final bool               hasPmi;
  final int?               pmiDropMonth; // month number when PMI drops to 0
  final List<AmortizationEntry> schedule;

  const MortgageResult({
    required this.loanAmount,
    required this.monthly,
    required this.totalInterest,
    required this.totalCost,
    required this.payoffDate,
    required this.currentLtv,
    required this.isJumbo,
    required this.hasPmi,
    this.pmiDropMonth,
    required this.schedule,
  });
}

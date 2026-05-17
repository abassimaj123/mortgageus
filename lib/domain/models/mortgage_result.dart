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

  double get piPayment => principal + interest;
  double get pitiPayment =>
      principal + interest + propertyTax + homeInsurance + hoa + pmi;
}

class MortgageResult {
  final double loanAmount;
  final MonthlyBreakdown monthly;
  final double totalInterest;
  final double totalCost;
  final DateTime payoffDate;
  final double currentLtv;
  final bool isJumbo;
  final bool hasPmi;
  final bool isUsda; // USDA loan — annual fee, never drops
  final int? pmiDropMonth; // month number when PMI drops to 0 (null for USDA)
  final List<AmortizationEntry> schedule;
  final double stressTestRate; // annualRatePct + 2.0
  final double stressTestMonthly; // P&I at stress rate

  const MortgageResult({
    required this.loanAmount,
    required this.monthly,
    required this.totalInterest,
    required this.totalCost,
    required this.payoffDate,
    required this.currentLtv,
    required this.isJumbo,
    required this.hasPmi,
    this.isUsda = false,
    this.pmiDropMonth,
    required this.schedule,
    required this.stressTestRate,
    required this.stressTestMonthly,
  });
}

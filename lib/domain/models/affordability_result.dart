class AffordabilityResult {
  final double maxHomePriceConservative; // 28% front-end DTI
  final double maxHomePriceStandard; // 43% back-end DTI
  final double maxLoanConservative;
  final double maxLoanStandard;
  final double monthlyPI;
  final double monthlyTax;
  final double monthlyInsurance;
  final double monthlyPMI;
  final double monthlyHOA;
  final double totalMonthly;
  final double inputDownPayment;
  final double monthlyGrossIncome;

  const AffordabilityResult({
    required this.maxHomePriceConservative,
    required this.maxHomePriceStandard,
    required this.maxLoanConservative,
    required this.maxLoanStandard,
    required this.monthlyPI,
    required this.monthlyTax,
    required this.monthlyInsurance,
    required this.monthlyPMI,
    required this.monthlyHOA,
    required this.totalMonthly,
    required this.inputDownPayment,
    required this.monthlyGrossIncome,
  });
}

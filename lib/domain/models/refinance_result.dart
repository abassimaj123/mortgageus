class RefinanceResult {
  final double oldMonthlyPayment;
  final double newMonthlyPayment;
  final double monthlySavings;
  final int    breakEvenMonths;
  final double totalSavingsOverLife;
  final bool   refinanceMakesSense; // break-even < 7 years

  const RefinanceResult({
    required this.oldMonthlyPayment,
    required this.newMonthlyPayment,
    required this.monthlySavings,
    required this.breakEvenMonths,
    required this.totalSavingsOverLife,
    required this.refinanceMakesSense,
  });
}

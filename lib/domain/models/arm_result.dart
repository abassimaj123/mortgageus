class ARMResult {
  final double payment1;          // monthly payment during fixed period
  final double payment2;          // monthly payment after rate reset
  final double balanceAtReset;    // remaining balance when ARM resets
  final double totalInterest;     // total interest over full term
  final double totalCost;         // loan + totalInterest
  final int    fixedMonths;       // number of months in fixed phase
  final double fixedPayment;      // equivalent fixed-rate 30yr payment for comparison
  final double fixedTotalInterest;
  final int?   breakEvenMonths;   // null if ARM is always cheaper (no crossover)

  const ARMResult({
    required this.payment1,
    required this.payment2,
    required this.balanceAtReset,
    required this.totalInterest,
    required this.totalCost,
    required this.fixedMonths,
    required this.fixedPayment,
    required this.fixedTotalInterest,
    this.breakEvenMonths,
  });
}

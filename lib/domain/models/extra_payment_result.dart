class ExtraPaymentResult {
  final int    originalPayoffMonths;
  final int    newPayoffMonths;
  final int    monthsSaved;
  final double originalTotalInterest;
  final double newTotalInterest;
  final double interestSaved;

  const ExtraPaymentResult({
    required this.originalPayoffMonths,
    required this.newPayoffMonths,
    required this.monthsSaved,
    required this.originalTotalInterest,
    required this.newTotalInterest,
    required this.interestSaved,
  });

  int get yearsSaved     => monthsSaved ~/ 12;
  int get remMonthsSaved => monthsSaved % 12;
}

class AmortizationEntry {
  final int     month;
  final DateTime date;
  final double  payment;
  final double  principal;
  final double  interest;
  final double  balance;
  final double  cumulativeInterest;
  final double  cumulativePrincipal;
  final double  pmiAmount;
  final bool    pmiDropped; // true on the first month PMI hits 0

  const AmortizationEntry({
    required this.month,
    required this.date,
    required this.payment,
    required this.principal,
    required this.interest,
    required this.balance,
    required this.cumulativeInterest,
    required this.cumulativePrincipal,
    required this.pmiAmount,
    this.pmiDropped = false,
  });
}

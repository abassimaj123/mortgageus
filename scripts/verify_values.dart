import '../lib/domain/usecases/mortgage_calculator.dart';

void main() {
  // PMI drop
  final s = MortgageCalculator.buildSchedule(
    loanAmount: 450000, annualRatePct: 6.5, termYears: 30,
    homePrice: 500000, pmiAnnualRatePct: 0.75,
    startDate: DateTime(2025, 1, 1),
  );
  final dropIdx = s.indexWhere((e) => e.pmiDropped);
  print('PMI drop index: $dropIdx  month: ${s[dropIdx].month}  '
      'balance: ${s[dropIdx].balance.toStringAsFixed(2)}');

  // Extra payments
  final ex = MortgageCalculator.calcExtraPayments(
    loanAmount: 320000, annualRatePct: 6.5, termYears: 30, extraMonthly: 200);
  print('monthsSaved: ${ex.monthsSaved}  yearsSaved: ${ex.yearsSaved}  '
      'interestSaved: ${ex.interestSaved.toStringAsFixed(0)}');

  // Refinance
  final r = MortgageCalculator.calcRefinance(
    currentBalance: 250000, currentRatePct: 7.0, currentYearsRemaining: 25,
    newRatePct: 5.5, newTermYears: 30, closingCosts: 5000);
  print('monthlySavings: ${r.monthlySavings.toStringAsFixed(2)}  '
      'breakEven: ${r.breakEvenMonths}');

  // Amortization first month
  final sch = MortgageCalculator.buildSchedule(
    loanAmount: 320000, annualRatePct: 6.5, termYears: 30,
    homePrice: 0, pmiAnnualRatePct: 0,
    startDate: DateTime(2025, 1, 1),
  );
  print('m1 interest: ${sch[0].interest.toStringAsFixed(2)}  '
      'principal: ${sch[0].principal.toStringAsFixed(2)}  '
      'balance: ${sch[0].balance.toStringAsFixed(2)}');
  final totalInterest = sch.fold<double>(0, (sum, e) => sum + e.interest);
  print('total interest: ${totalInterest.toStringAsFixed(0)}');
  print('last balance: ${sch.last.balance.toStringAsFixed(4)}');
}

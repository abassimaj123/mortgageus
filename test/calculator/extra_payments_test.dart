import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

void main() {
  group('calcExtraPayments', () {

    test('Extra \$200/mo on \$320k @ 6.5%/30yr saves ~79 months (~6yr 7mo)', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount:    320000,
        annualRatePct: 6.5,
        termYears:     30,
        extraMonthly:  200,
      );
      expect(r.monthsSaved, closeTo(79, 3));
      expect(r.yearsSaved,  equals(6)); // int: 79 ~/ 12 = 6
    });

    test('Extra \$200/mo on \$320k @ 6.5%/30yr saves ~\$105,429 interest', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount:    320000,
        annualRatePct: 6.5,
        termYears:     30,
        extraMonthly:  200,
      );
      expect(r.interestSaved, closeTo(105429, 2000));
    });

    test('Extra \$0/mo → 0 months saved', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount:    320000,
        annualRatePct: 6.5,
        termYears:     30,
        extraMonthly:  0,
      );
      expect(r.monthsSaved, equals(0));
      expect(r.interestSaved, closeTo(0, 1));
    });

    test('Extra payment > remaining balance: saves full term', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount:    100000,
        annualRatePct: 6.5,
        termYears:     30,
        extraMonthly:  10000, // pays off in month 1
      );
      expect(r.monthsSaved, greaterThan(300));
      expect(r.interestSaved, greaterThan(0));
    });

    test('New payoff months < original payoff months when extra > 0', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount:    300000,
        annualRatePct: 5.5,
        termYears:     30,
        extraMonthly:  150,
      );
      expect(r.newPayoffMonths, lessThan(r.originalPayoffMonths));
    });

    test('Original total interest matches standalone schedule total', () {
      final r = MortgageCalculator.calcExtraPayments(
        loanAmount:    300000,
        annualRatePct: 6.5,
        termYears:     30,
        extraMonthly:  0,
      );
      final schedule = MortgageCalculator.buildSchedule(
        loanAmount: 300000, annualRatePct: 6.5, termYears: 30,
        homePrice: 0, pmiAnnualRatePct: 0, startDate: DateTime(2025, 1, 1),
      );
      final scheduleInterest = schedule.fold<double>(0, (s, e) => s + e.interest);
      expect(r.originalTotalInterest, closeTo(scheduleInterest, 1));
    });
  });
}

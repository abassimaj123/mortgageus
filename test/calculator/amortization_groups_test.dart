import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';
import 'package:mortgage_us/domain/models/amortization_entry.dart';

// ── Mirror of the private grouping logic (tested via its outputs) ─────────────

class _YearGroup {
  final int    yearIndex;
  final int    calendarYear;
  final List<AmortizationEntry> months;
  final double yearlyInterest;
  final double yearlyPrincipal;
  final double endBalance;
  final bool   hasPmiDrop;
  final bool   isHalfway;
  final bool   isLastYear;
  final double pctPaid;

  const _YearGroup({
    required this.yearIndex,
    required this.calendarYear,
    required this.months,
    required this.yearlyInterest,
    required this.yearlyPrincipal,
    required this.endBalance,
    required this.hasPmiDrop,
    required this.isHalfway,
    required this.isLastYear,
    required this.pctPaid,
  });
}

List<_YearGroup> buildYearGroups(
  List<AmortizationEntry> schedule,
  double loanAmount,
) {
  final groups     = <_YearGroup>[];
  final halfPaid   = loanAmount / 2;
  bool  halfFlagged = false;

  for (int y = 0; y < (schedule.length / 12).ceil(); y++) {
    final start  = y * 12;
    final end    = (start + 12).clamp(0, schedule.length);
    final months = schedule.sublist(start, end);

    final interest  = months.fold<double>(0, (s, e) => s + e.interest);
    final principal = months.fold<double>(0, (s, e) => s + e.principal);
    final endBal    = months.last.balance;
    final paid      = loanAmount - endBal;
    final pct       = (paid / loanAmount * 100).clamp(0.0, 100.0);

    final hasPmiDrop = months.any((e) => e.pmiDropped);
    final isLast     = y == (schedule.length / 12).ceil() - 1;

    bool isHalf = false;
    if (!halfFlagged && paid >= halfPaid) {
      isHalf = true;
      halfFlagged = true;
    }

    groups.add(_YearGroup(
      yearIndex:    y + 1,
      calendarYear: months.first.date.year,
      months:       months,
      yearlyInterest:  interest,
      yearlyPrincipal: principal,
      endBalance:   endBal,
      hasPmiDrop:   hasPmiDrop,
      isHalfway:    isHalf,
      isLastYear:   isLast,
      pctPaid:      pct,
    ));
  }
  return groups;
}

// ── Tests ─────────────────────────────────────────────────────────────────────
void main() {
  late List<AmortizationEntry> schedule30;
  late List<_YearGroup>        groups30;
  const loanAmount = 320000.0;

  setUpAll(() {
    schedule30 = MortgageCalculator.buildSchedule(
      loanAmount:       loanAmount,
      annualRatePct:    6.5,
      termYears:        30,
      homePrice:        0,
      pmiAnnualRatePct: 0,
      startDate:        DateTime(2025, 1, 1),
    );
    groups30 = buildYearGroups(schedule30, loanAmount);
  });

  group('Amortization yearly grouping', () {

    test('Groups correctly by 12 months per year (30yr → 30 groups)', () {
      expect(groups30.length, equals(30));
    });

    test('Each full year has exactly 12 months', () {
      for (final g in groups30.take(29)) { // last year may have fewer
        expect(g.months.length, equals(12));
      }
    });

    test('First group = Year 1 starting in 2025', () {
      expect(groups30.first.yearIndex,    equals(1));
      expect(groups30.first.calendarYear, equals(2025));
    });

    test('Last group is flagged as isLastYear', () {
      expect(groups30.last.isLastYear, isTrue);
      expect(groups30.take(29).every((g) => !g.isLastYear), isTrue);
    });
  });

  group('Yearly summary totals', () {

    test('Yearly totals sum to full schedule totals', () {
      final sumInterest  = groups30.fold<double>(0, (s, g) => s + g.yearlyInterest);
      final sumPrincipal = groups30.fold<double>(0, (s, g) => s + g.yearlyPrincipal);
      final fullInterest  = schedule30.fold<double>(0, (s, e) => s + e.interest);
      final fullPrincipal = schedule30.fold<double>(0, (s, e) => s + e.principal);

      expect(sumInterest,  closeTo(fullInterest,  1.0));
      expect(sumPrincipal, closeTo(fullPrincipal, 1.0));
    });

    test('End balance of last year ≈ \$0', () {
      expect(groups30.last.endBalance, closeTo(0, 0.50));
    });

    test('pctPaid increases monotonically', () {
      for (int i = 1; i < groups30.length; i++) {
        expect(groups30[i].pctPaid, greaterThan(groups30[i - 1].pctPaid));
      }
    });

    test('pctPaid at last year ≈ 100%', () {
      expect(groups30.last.pctPaid, closeTo(100.0, 0.5));
    });
  });

  group('PMI drop year flagging', () {

    test('PMI drop year is flagged on loan with PMI', () {
      final sched = MortgageCalculator.buildSchedule(
        loanAmount:       450000,
        annualRatePct:    6.5,
        termYears:        30,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
        startDate:        DateTime(2025, 1, 1),
      );
      final groups = buildYearGroups(sched, 450000);
      final pmiYears = groups.where((g) => g.hasPmiDrop).toList();

      expect(pmiYears.length, equals(1));           // drops exactly once
      expect(pmiYears.first.yearIndex, greaterThan(8)); // not in first 8 years
    });

    test('No PMI flag on 20% down loan', () {
      final sched = MortgageCalculator.buildSchedule(
        loanAmount:       400000,
        annualRatePct:    6.5,
        termYears:        30,
        homePrice:        500000,
        pmiAnnualRatePct: 0.75,
        startDate:        DateTime(2025, 1, 1),
      );
      final groups = buildYearGroups(sched, 400000);
      expect(groups.every((g) => !g.hasPmiDrop), isTrue);
    });
  });

  group('Halfway year flagging', () {

    test('Exactly one year is flagged as isHalfway', () {
      final halfYears = groups30.where((g) => g.isHalfway).toList();
      expect(halfYears.length, equals(1));
    });

    test('Halfway year: paid amount ≥ 50% of loan', () {
      final halfGroup = groups30.firstWhere((g) => g.isHalfway);
      final paid = loanAmount - halfGroup.endBalance;
      expect(paid, greaterThanOrEqualTo(loanAmount / 2));
    });

    test('Year before halfway: paid amount < 50% of loan', () {
      final halfIdx = groups30.indexWhere((g) => g.isHalfway);
      if (halfIdx > 0) {
        final paid = loanAmount - groups30[halfIdx - 1].endBalance;
        expect(paid, lessThan(loanAmount / 2));
      }
    });

    test('Halfway year is in second half of loan term (year > 15 at 6.5%)', () {
      // At 6.5%, interest-heavy early payments → halfway hits after year 20
      final halfGroup = groups30.firstWhere((g) => g.isHalfway);
      expect(halfGroup.yearIndex, greaterThan(15));
    });
  });
}

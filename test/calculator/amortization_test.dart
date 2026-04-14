import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/domain/usecases/mortgage_calculator.dart';

List<dynamic> _schedule(double loan, double rateDecimal, int years) =>
    MortgageCalculator.buildSchedule(
      loanAmount:       loan,
      annualRatePct:    rateDecimal * 100,
      termYears:        years,
      homePrice:        0,
      pmiAnnualRatePct: 0,
      startDate:        DateTime(2025, 1, 1),
    );

void main() {
  group('buildSchedule — month 1 breakdown', () {

    test('First month interest on \$320k at 6.5% = \$1,733.33', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s[0].interest, closeTo(1733.33, 0.01));
    });

    test('First month principal on \$320k at 6.5% = \$289.28', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s[0].principal, closeTo(289.28, 0.10)); // varies by rounding
    });

    test('First month balance on \$320k at 6.5% = \$319,710.72', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s[0].balance, closeTo(319710.72, 0.50));
    });

    test('First month: interest > principal (early-loan skew)', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s[0].interest, greaterThan(s[0].principal));
    });

    test('Last month: principal > interest (late-loan skew)', () {
      final s = _schedule(320000, 0.065, 30);
      final last = s.last;
      expect(last.principal, greaterThan(last.interest));
    });
  });

  group('buildSchedule — totals', () {

    test('Total interest \$320k @ 6.5% / 30yr ≈ \$408,142', () {
      final s = _schedule(320000, 0.065, 30);
      final total = s.fold<double>(0, (sum, e) => sum + e.interest);
      expect(total, closeTo(408142, 100));
    });

    test('Last month balance is approximately \$0', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s.last.balance, closeTo(0, 0.50));
    });

    test('30yr schedule has 360 entries', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s.length, equals(360));
    });

    test('15yr schedule has 180 entries', () {
      final s = _schedule(200000, 0.05, 15);
      expect(s.length, equals(180));
    });

    test('Cumulative principal in last entry ≈ loan amount', () {
      final s = _schedule(320000, 0.065, 30);
      expect(s.last.cumulativePrincipal, closeTo(320000, 1.0));
    });

    test('Each entry: payment = principal + interest (±\$0.01)', () {
      final s = _schedule(300000, 0.065, 30);
      // All entries except the last (lump-sum adjusted)
      for (final e in s.take(s.length - 1)) {
        expect(e.payment, closeTo(e.principal + e.interest, 0.01));
      }
    });
  });

  group('buildSchedule — balance progression', () {

    test('Balance strictly decreases (principal always positive)', () {
      final s = _schedule(320000, 0.065, 30);
      for (int i = 1; i < s.length; i++) {
        expect(s[i].balance, lessThan(s[i - 1].balance));
      }
    });

    test('0% rate: equal principal every month', () {
      final s = _schedule(120000, 0.0, 10); // 120k / 120mo = $1000/mo
      for (final e in s) {
        expect(e.interest, equals(0.0));
        expect(e.principal, closeTo(1000.0, 0.01));
      }
    });
  });
}

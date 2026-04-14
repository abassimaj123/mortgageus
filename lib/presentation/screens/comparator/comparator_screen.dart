import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../domain/models/mortgage_result.dart';
import '../../providers/mortgage_providers.dart';

class ComparatorScreen extends ConsumerWidget {
  const ComparatorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s   = ref.watch(mortgageInputProvider);
    final fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
    final fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month + 1);
    final loan = s.homePrice - s.downPaymentDollar;

    MortgageResult? calc(int termYears) {
      if (s.homePrice <= 0 || loan < 0 || s.annualRatePct < 0) return null;
      try {
        final input = MortgageInput(
          homePrice:            s.homePrice,
          downPayment:          s.downPaymentDollar,
          annualRatePct:        s.annualRatePct,
          termYears:            termYears,
          loanType:             s.loanType,
          propertyTaxRatePct:   s.propertyTaxRatePct,
          homeInsuranceAnnual:  s.homeInsuranceAnnual,
          hoaMonthly:           s.hoaMonthly,
          pmiAnnualRatePct:     0.0,
          startDate:            startDate,
        );
        return MortgageCalculator.calculate(input);
      } catch (_) {
        return null;
      }
    }

    final r30 = calc(30);
    final r15 = calc(15);

    return Scaffold(
      appBar: AppBar(title: const Text('Loan Comparator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header info
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: AppTheme.primary.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.home, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Home: ${fmt.format(s.homePrice)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Down: ${fmt.format(s.downPaymentDollar)}'
                    ' (${s.downPaymentPct.toStringAsFixed(1)}%)'
                    '  Rate: ${s.annualRatePct}%',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Scenario Comparison',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text('Same loan, different terms — see which works best for you.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 16),
          if (r30 == null || r15 == null)
            const Center(child: Text('Enter valid loan details in Calculator tab'))
          else
            _CompareTable(r30: r30, r15: r15, fmt: fmt, fmtK: fmtK),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  final MortgageResult r30, r15;
  final NumberFormat   fmt, fmtK;
  const _CompareTable({
    required this.r30, required this.r15,
    required this.fmt, required this.fmtK,
  });

  @override
  Widget build(BuildContext context) {
    // 15yr wins on interest; 30yr wins on monthly payment
    return Column(children: [
      // Column headers
      Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(flex: 4, child: _ScenarioHeader('30-Year', AppTheme.primary)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: _ScenarioHeader('15-Year', AppTheme.accentGood)),
      ]),
      const SizedBox(height: 12),
      _CompareRow(
        label: 'Monthly P&I',
        val30: fmt.format(r30.monthly.piPayment),
        val15: fmt.format(r15.monthly.piPayment),
        winner: 30, // 30yr lower monthly
      ),
      _CompareRow(
        label: 'Monthly PITI',
        val30: fmt.format(r30.monthly.pitiPayment),
        val15: fmt.format(r15.monthly.pitiPayment),
        winner: 30,
      ),
      _CompareRow(
        label: 'Total Interest',
        val30: fmtK.format(r30.totalInterest),
        val15: fmtK.format(r15.totalInterest),
        winner: 15, // 15yr saves interest
      ),
      _CompareRow(
        label: 'Total Cost',
        val30: fmtK.format(r30.totalCost),
        val15: fmtK.format(r15.totalCost),
        winner: 15,
      ),
      _CompareRow(
        label: 'Payoff Date',
        val30: '${r30.payoffDate.month}/${r30.payoffDate.year}',
        val15: '${r15.payoffDate.month}/${r15.payoffDate.year}',
        winner: 15, // 15yr payoff sooner
      ),
      const SizedBox(height: 16),
      // Savings callout
      Card(
        color: AppTheme.accentGood.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTheme.accentGood.withOpacity(0.4))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('15-Year Advantage',
              style: TextStyle(
                color: AppTheme.accentGood,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              )),
            const SizedBox(height: 8),
            Text('Interest saved: ${fmtK.format(r30.totalInterest - r15.totalInterest)}',
              style: const TextStyle(fontSize: 13)),
            Text('Paid off: ${(r30.payoffDate.year - r15.payoffDate.year)} years earlier',
              style: const TextStyle(fontSize: 13)),
            const Divider(height: 20),
            Text('30-Year Advantage',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              )),
            const SizedBox(height: 8),
            Text('Monthly savings: ${fmt.format(r15.monthly.piPayment - r30.monthly.piPayment)} lower',
              style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ),
    ]);
  }
}

class _ScenarioHeader extends StatelessWidget {
  final String label;
  final Color  color;
  const _ScenarioHeader(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      )),
  );
}

class _CompareRow extends StatelessWidget {
  final String label, val30, val15;
  final int    winner; // 30 or 15 = which scenario wins
  const _CompareRow({
    required this.label,
    required this.val30,
    required this.val15,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(flex: 3,
          child: Text(label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
        Expanded(flex: 4,
          child: _ValueCell(val30, isWinner: winner == 30, color: AppTheme.primary)),
        const SizedBox(width: 8),
        Expanded(flex: 4,
          child: _ValueCell(val15, isWinner: winner == 15, color: AppTheme.accentGood)),
      ]),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String value;
  final bool   isWinner;
  final Color  color;
  const _ValueCell(this.value, {required this.isWinner, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: isWinner ? color.withOpacity(0.12) : null,
      borderRadius: BorderRadius.circular(8),
      border: isWinner
        ? Border.all(color: color.withOpacity(0.4))
        : null,
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (isWinner) ...[
        Icon(Icons.check_circle, size: 14, color: color),
        const SizedBox(width: 4),
      ],
      Flexible(child: Text(value,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
          color: isWinner ? color : null,
        ))),
    ]),
  );
}

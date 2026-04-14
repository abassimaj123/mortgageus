import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/extra_payment_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';

class ExtraPaymentsScreen extends ConsumerStatefulWidget {
  const ExtraPaymentsScreen({super.key});
  @override
  ConsumerState<ExtraPaymentsScreen> createState() => _ExtraPaymentsScreenState();
}

class _ExtraPaymentsScreenState extends ConsumerState<ExtraPaymentsScreen> {
  final _extraMonthlyCtrl = TextEditingController(text: '200');
  final _extraAnnualCtrl  = TextEditingController(text: '0');
  final _lumpSumCtrl      = TextEditingController(text: '0');
  final _lumpMonthCtrl    = TextEditingController(text: '12');

  ExtraPaymentResult? _result;
  final _fmt  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  @override
  void dispose() {
    _extraMonthlyCtrl.dispose();
    _extraAnnualCtrl.dispose();
    _lumpSumCtrl.dispose();
    _lumpMonthCtrl.dispose();
    super.dispose();
  }

  void _calculate(MortgageInputState s) {
    final loan       = s.homePrice - s.downPaymentDollar;
    if (loan <= 0) return;
    final extraMonthly = double.tryParse(_extraMonthlyCtrl.text) ?? 0;
    final extraAnnual  = double.tryParse(_extraAnnualCtrl.text)  ?? 0;
    final lumpSum      = double.tryParse(_lumpSumCtrl.text)      ?? 0;
    final lumpMonth    = int.tryParse(_lumpMonthCtrl.text)        ?? 0;

    setState(() {
      try {
        _result = MortgageCalculator.calcExtraPayments(
          loanAmount:   loan,
          annualRatePct: s.annualRatePct,
          termYears:    s.termYears,
          extraMonthly: extraMonthly,
          extraAnnual:  extraAnnual,
          lumpSum:      lumpSum,
          lumpSumMonth: lumpMonth,
        );
      } catch (_) {
        _result = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inputState = ref.watch(mortgageInputProvider);
    final r          = _result;
    final loan       = inputState.homePrice - inputState.downPaymentDollar;
    final extraMonthly = double.tryParse(_extraMonthlyCtrl.text) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Extra Payment Calculator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Loan summary
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: AppTheme.primary.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.home, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Loan: ${_fmt.format(loan)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${inputState.annualRatePct}% for ${inputState.termYears} years',
                    style: const TextStyle(color: Colors.grey)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Extra Payments',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _field('Extra Monthly Payment', _extraMonthlyCtrl, prefix: '\$'),
          _field('Extra Annual Payment', _extraAnnualCtrl, prefix: '\$'),
          _field('Lump Sum Payment', _lumpSumCtrl, prefix: '\$'),
          _field('Lump Sum in Month #', _lumpMonthCtrl),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _calculate(inputState),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: const Text('Calculate Savings', style: TextStyle(fontSize: 16)),
            ),
          ),
          // Big CTA
          if (r != null && extraMonthly > 0) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.accentGood, Color(0xFF43A047)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                const Icon(Icons.savings, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                Text(
                  'You could save ${_fmt.format(r.interestSaved)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'by paying ${_fmt.format(extraMonthly)} extra/month',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ],
          if (r != null) ...[
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _ResultRow('Original Payoff',
                    '${r.originalPayoffMonths} months'
                    ' (${r.originalPayoffMonths ~/ 12} yrs)'),
                  _ResultRow('New Payoff',
                    '${r.newPayoffMonths} months'
                    ' (${r.newPayoffMonths ~/ 12} yrs)'),
                  _ResultRow('Time Saved',
                    '${r.yearsSaved} yrs ${r.remMonthsSaved} mo',
                    color: AppTheme.accentGood),
                  const Divider(height: 24),
                  _ResultRow('Original Total Interest',
                    _fmt.format(r.originalTotalInterest)),
                  _ResultRow('New Total Interest',
                    _fmt.format(r.newTotalInterest)),
                  _ResultRow('Interest Saved',
                    _fmt.format(r.interestSaved),
                    color: AppTheme.accentGood,
                    bold: true),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  final bool   bold;
  const _ResultRow(this.label, this.value, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.grey)),
      Text(value, style: TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        color: color,
      )),
    ]),
  );
}

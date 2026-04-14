import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../domain/models/refinance_result.dart';

class RefinanceScreen extends StatefulWidget {
  const RefinanceScreen({super.key});
  @override
  State<RefinanceScreen> createState() => _RefinanceScreenState();
}

class _RefinanceScreenState extends State<RefinanceScreen> {
  final _balanceCtrl  = TextEditingController(text: '300000');
  final _curRateCtrl  = TextEditingController(text: '7.0');
  final _curYearsCtrl = TextEditingController(text: '25');
  final _newRateCtrl  = TextEditingController(text: '6.0');
  final _newYearsCtrl = TextEditingController(text: '30');
  final _closingCtrl  = TextEditingController(text: '4000');

  RefinanceResult? _result;
  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

  @override
  void dispose() {
    _balanceCtrl.dispose();
    _curRateCtrl.dispose();
    _curYearsCtrl.dispose();
    _newRateCtrl.dispose();
    _newYearsCtrl.dispose();
    _closingCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final balance  = double.tryParse(_balanceCtrl.text.replaceAll(',', ''))  ?? 0;
    final curRate  = double.tryParse(_curRateCtrl.text)  ?? 0;
    final curYears = int.tryParse(_curYearsCtrl.text)    ?? 25;
    final newRate  = double.tryParse(_newRateCtrl.text)  ?? 0;
    final newYears = int.tryParse(_newYearsCtrl.text)    ?? 30;
    final closing  = double.tryParse(_closingCtrl.text.replaceAll(',', '')) ?? 4000;

    if (balance <= 0 || curYears <= 0 || newYears <= 0) return;

    setState(() {
      try {
        _result = MortgageCalculator.calcRefinance(
          currentBalance:        balance,
          currentRatePct:        curRate,
          currentYearsRemaining: curYears,
          newRatePct:            newRate,
          newTermYears:          newYears,
          closingCosts:          closing,
        );
      } catch (_) {
        _result = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Refinance Calculator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Section('Current Loan', [
            _field('Current Balance', _balanceCtrl, prefix: '\$', currency: true),
            _field('Current Rate (%)', _curRateCtrl, suffix: '%'),
            _field('Years Remaining', _curYearsCtrl, suffix: 'yrs'),
          ]),
          const SizedBox(height: 16),
          _Section('New Loan', [
            _field('New Rate (%)', _newRateCtrl, suffix: '%'),
            _field('New Term', _newYearsCtrl, suffix: 'yrs'),
            _field('Closing Costs', _closingCtrl, prefix: '\$', currency: true),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _calculate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16)),
              child: const Text('Calculate Refinance',
                style: TextStyle(fontSize: 16)),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _ResultRow('Current Payment', _fmt.format(r.oldMonthlyPayment)),
                  _ResultRow('New Payment',     _fmt.format(r.newMonthlyPayment)),
                  _ResultRow('Monthly Savings', _fmt.format(r.monthlySavings),
                    color: r.monthlySavings > 0
                      ? AppTheme.accentGood
                      : Colors.red),
                  const Divider(height: 24),
                  _ResultRow('Break-Even',
                    '${r.breakEvenMonths} months'
                    ' (${(r.breakEvenMonths / 12).toStringAsFixed(1)} yrs)'),
                  _ResultRow('Total Savings Over Life',
                    _fmt.format(r.totalSavingsOverLife),
                    color: r.totalSavingsOverLife > 0
                      ? AppTheme.accentGood
                      : Colors.red),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: r.refinanceMakesSense
                          ? AppTheme.accentGood.withOpacity(0.1)
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: r.refinanceMakesSense
                          ? AppTheme.accentGood
                          : Colors.red),
                    ),
                    child: Text(
                      r.refinanceMakesSense
                          ? 'Refinancing makes sense — break-even in'
                            ' ${r.breakEvenMonths} months'
                          : 'Refinancing may not make sense'
                            ' (break-even > 7 years)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: r.refinanceMakesSense
                          ? AppTheme.accentGood
                          : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
      {String? prefix, String? suffix, bool currency = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: currency ? [CurrencyInputFormatter()] : null,
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

class _Section extends StatelessWidget {
  final String       title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 12),
      ...children,
    ],
  );
}

class _ResultRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _ResultRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.grey)),
      Text(value,
        style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ]),
  );
}

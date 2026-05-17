import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../domain/models/refinance_result.dart';
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart'
    show PaywallTrigger, CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';

class RefinanceScreen extends StatefulWidget {
  const RefinanceScreen({super.key});
  @override
  State<RefinanceScreen> createState() => _RefinanceScreenState();
}

class _RefinanceScreenState extends State<RefinanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _balanceCtrl = TextEditingController(text: '300000');
  final _curRateCtrl = TextEditingController(text: '7.0');
  final _curYearsCtrl = TextEditingController(text: '25');
  final _newRateCtrl = TextEditingController(text: '6.0');
  final _newYearsCtrl = TextEditingController(text: '30');
  final _closingCtrl = TextEditingController(text: '4000');

  RefinanceResult? _result;
  String? _balanceError;
  final _fmt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
  }

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

  Future<void> _calculate() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final balance = double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0;
    final curRate = double.tryParse(_curRateCtrl.text) ?? 0;
    final curYears = int.tryParse(_curYearsCtrl.text) ?? 25;
    final newRate = double.tryParse(_newRateCtrl.text) ?? 0;
    final newYears = int.tryParse(_newYearsCtrl.text) ?? 30;
    final closing =
        double.tryParse(_closingCtrl.text.replaceAll(',', '')) ?? 4000;

    if (balance <= 0 || curYears <= 0 || newYears <= 0) {
      setState(() =>
          _balanceError = balance <= 0 ? 'Enter a valid loan balance' : null);
      return;
    }
    setState(() => _balanceError = null);

    setState(() {
      try {
        _result = MortgageCalculator.calcRefinance(
          currentBalance: balance,
          currentRatePct: curRate,
          currentYearsRemaining: curYears,
          newRatePct: newRate,
          newTermYears: newYears,
          closingCosts: closing,
        );
      } catch (_) {
        _result = null;
      }
    });
    adService.onAction();
    AnalyticsService.instance.logRefinanceSimulated();
    if (mounted) {
      final trigger = await paywallSession.recordAction();
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          appBar: AppBar(title: Text((s.refiTitle as String))),
          body: Column(
            children: [
              Expanded(
                  child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Section((s.currentLoan as String), [
                          _field((s.currentBalance as String), _balanceCtrl,
                              prefix: '\$',
                              currency: true,
                              errorText: _balanceError,
                              required: true),
                          _field((s.currentRate as String), _curRateCtrl,
                              suffix: '%', required: true),
                          _field((s.yearsRemaining as String), _curYearsCtrl,
                              suffix: s.years as String?, required: true),
                        ]),
                        const SizedBox(height: 16),
                        _Section((s.newLoan as String), [
                          _field((s.newRate as String), _newRateCtrl,
                              suffix: '%', required: true),
                          _field((s.newTerm as String), _newYearsCtrl,
                              suffix: s.years as String?, required: true),
                          _field((s.closingCosts as String), _closingCtrl,
                              prefix: '\$', currency: true),
                        ]),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _calculate,
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(AppSpacing.lg)),
                            child: Text((s.calcRefi as String),
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg)),
                          ),
                        ),
                        if (r != null) ...[
                          const SizedBox(height: 20),
                          Card(
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl)),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(children: [
                                _ResultRow((s.currentPayment as String),
                                    _fmt.format(r.oldMonthlyPayment)),
                                _ResultRow((s.newPayment as String),
                                    _fmt.format(r.newMonthlyPayment)),
                                _ResultRow((s.monthlySavings as String),
                                    _fmt.format(r.monthlySavings),
                                    color: r.monthlySavings > 0
                                        ? AppTheme.accentGood
                                        : Colors.red),
                                const Divider(height: 24),
                                _ResultRow(
                                    (s.breakEven as String),
                                    r.monthlySavings <= 0
                                        ? (isEs
                                            ? 'N/A — tasa más alta'
                                            : 'N/A — higher rate')
                                        : r.breakEvenMonths > 9999
                                            ? (isEs
                                                ? 'N/A — nunca'
                                                : 'N/A — never')
                                            : '${r.breakEvenMonths} ${s.months}'
                                                ' (${(r.breakEvenMonths / 12).toStringAsFixed(1)} yrs)'),
                                _ResultRow((s.totalSavings as String),
                                    _fmt.format(r.totalSavingsOverLife),
                                    color: r.totalSavingsOverLife > 0
                                        ? AppTheme.accentGood
                                        : Colors.red),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: r.refinanceMakesSense
                                        ? AppTheme.accentGood
                                            .withValues(alpha: 0.1)
                                        : Colors.red.shade50,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.lg),
                                    border: Border.all(
                                        color: r.refinanceMakesSense
                                            ? AppTheme.accentGood
                                            : Colors.red),
                                  ),
                                  child: Text(
                                    r.refinanceMakesSense
                                        ? '${s.refiMakesSense} ${r.breakEvenMonths} ${s.months}'
                                        : r.monthlySavings <= 0
                                            ? (isEs
                                                ? 'La nueva tasa es mayor — el refinanciamiento cuesta más'
                                                : 'New rate is higher — refinancing costs more')
                                            : '${s.refiMayNot} ${s.breakEvenLong}',
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
                ), // Form closes
              )),
              const CalcwiseAdFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix,
      String? suffix,
      bool currency = false,
      String? errorText,
      bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: currency ? [CurrencyInputFormatter()] : null,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
          errorText: errorText,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (v) {
          final raw = (v ?? '').trim();
          if (raw.isEmpty) return required ? 'Required' : null;
          final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
          if (cleaned.isEmpty) return 'Invalid';
          final n = double.tryParse(cleaned);
          if (n == null) return 'Invalid';
          if (n < 0) return 'Must be ≥ 0';
          return null;
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyLg)),
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
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: AppTheme.labelGray)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

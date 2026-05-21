import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../domain/models/refinance_result.dart';
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart'
    show PaywallTrigger, CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
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
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          appBar: AppBar(title: Text(s.refiTitle)),
          body: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Section(s.currentLoan, [
                          _field(s.currentBalance, _balanceCtrl,
                              prefix: '\$',
                              currency: true,
                              errorText: _balanceError,
                              required: true),
                          _field(s.currentRate, _curRateCtrl,
                              suffix: '%', required: true),
                          _field(s.yearsRemaining, _curYearsCtrl,
                              suffix: s.years as String?, required: true),
                        ]),
                        const SizedBox(height: AppSpacing.lg),
                        _Section(s.newLoan, [
                          _field(s.newRate, _newRateCtrl,
                              suffix: '%', required: true),
                          _field(s.newTerm, _newYearsCtrl,
                              suffix: s.years as String?, required: true),
                          _field(s.closingCosts, _closingCtrl,
                              prefix: '\$', currency: true),
                        ]),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _calculate,
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(AppSpacing.lg)),
                            child: Text(s.calcRefi,
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyLg)),
                          ),
                        ),
                        if (r != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Card(
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl)),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(children: [
                                _ResultRow(s.currentPayment,
                                    _fmt.format(r.oldMonthlyPayment)),
                                _ResultRow(s.newPayment,
                                    _fmt.format(r.newMonthlyPayment)),
                                _ResultRow(s.monthlySavings,
                                    _fmt.format(r.monthlySavings),
                                    color: r.monthlySavings > 0
                                        ? AppTheme.accentGood
                                        : CalcwiseSemanticColors.errorDark),
                                const Divider(height: 24),
                                _ResultRow(
                                    s.breakEven,
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
                                _ResultRow(s.totalSavings,
                                    _fmt.format(r.totalSavingsOverLife),
                                    color: r.totalSavingsOverLife > 0
                                        ? AppTheme.accentGood
                                        : CalcwiseSemanticColors.errorDark),
                                const SizedBox(height: AppSpacing.md),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: r.refinanceMakesSense
                                        ? AppTheme.accentGood
                                            .withValues(alpha: 0.1)
                                        : CalcwiseSemanticColors.errorBg,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.lg),
                                    border: Border.all(
                                        color: r.refinanceMakesSense
                                            ? AppTheme.accentGood
                                            : CalcwiseSemanticColors.errorDark),
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
                                          : CalcwiseSemanticColors.errorDark,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final text = isEs
                                      ? '📊 Refinanciamiento\n'
                                        'Pago actual: ${_fmt.format(r!.oldMonthlyPayment)}/mes\n'
                                        'Nuevo pago: ${_fmt.format(r!.newMonthlyPayment)}/mes\n'
                                        'Ahorro mensual: ${_fmt.format(r!.monthlySavings)}\n'
                                        '— MortgageUS'
                                      : '📊 Refinance Summary\n'
                                        'Current payment: ${_fmt.format(r!.oldMonthlyPayment)}/mo\n'
                                        'New payment: ${_fmt.format(r!.newMonthlyPayment)}/mo\n'
                                        'Monthly savings: ${_fmt.format(r!.monthlySavings)}\n'
                                        '— MortgageUS';
                                  await Share.share(text);
                                },
                                icon: const Icon(Icons.share_rounded),
                                label: Text(isEs ? 'Compartir' : 'Share'),
                              ),
                            ),
                          ]),
                        ],
                        const SizedBox(height: AppSpacing.listBottomInset),
                      ]),
                ), // Form closes
              )))),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
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
          const SizedBox(height: AppSpacing.md),
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: AppTheme.labelGray)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../domain/models/extra_payment_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart'
    show PaywallTrigger, CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';

class ExtraPaymentsScreen extends ConsumerStatefulWidget {
  const ExtraPaymentsScreen({super.key});
  @override
  ConsumerState<ExtraPaymentsScreen> createState() =>
      _ExtraPaymentsScreenState();
}

class _ExtraPaymentsScreenState extends ConsumerState<ExtraPaymentsScreen> {
  final _extraMonthlyCtrl = TextEditingController(text: '200');
  final _extraAnnualCtrl = TextEditingController(text: '0');
  final _lumpSumCtrl = TextEditingController(text: '0');
  final _lumpMonthCtrl = TextEditingController(text: '12');

  ExtraPaymentResult? _result;
  final _fmt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _extraMonthlyCtrl.dispose();
    _extraAnnualCtrl.dispose();
    _lumpSumCtrl.dispose();
    _lumpMonthCtrl.dispose();
    super.dispose();
  }

  Future<void> _calculate(MortgageInputState s) async {
    final loan = s.homePrice - s.downPaymentDollar;
    if (loan <= 0) return;
    final extraMonthly =
        double.tryParse(_extraMonthlyCtrl.text.replaceAll(',', '')) ?? 0;
    final extraAnnual =
        double.tryParse(_extraAnnualCtrl.text.replaceAll(',', '')) ?? 0;
    final lumpSum = double.tryParse(_lumpSumCtrl.text.replaceAll(',', '')) ?? 0;
    final lumpMonth = int.tryParse(_lumpMonthCtrl.text) ?? 0;

    setState(() {
      try {
        _result = MortgageCalculator.calcExtraPayments(
          loanAmount: loan,
          annualRatePct: s.annualRatePct,
          termYears: s.termYears,
          extraMonthly: extraMonthly,
          extraAnnual: extraAnnual,
          lumpSum: lumpSum,
          lumpSumMonth: lumpMonth,
        );
      } catch (_) {
        _result = null;
      }
    });
    adService.onAction();
    AnalyticsService.instance.logExtraPaymentSimulated();
    if (mounted) {
      final trigger = await paywallSession.recordAction();
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputState = ref.watch(mortgageInputProvider);
    final r = _result;
    final loan = inputState.homePrice - inputState.downPaymentDollar;
    final extraMonthly =
        double.tryParse(_extraMonthlyCtrl.text.replaceAll(',', '')) ?? 0;
    final extraAnnual =
        double.tryParse(_extraAnnualCtrl.text.replaceAll(',', '')) ?? 0;
    final lumpSum =
        double.tryParse(_lumpSumCtrl.text.replaceAll(',', '')) ?? 0;

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          appBar: AppBar(title: Text(s.extraTitle)),
          body: Column(
            children: [
              Expanded(
                  child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Loan summary
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border:
                                  Border.all(color: AppTheme.primary, width: 1),
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: Row(children: [
                              const Icon(Icons.home_rounded,
                                  color: AppTheme.primary),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('${s.loan} ${_fmt.format(loan)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary,
                                        )),
                                    Text(
                                        '${inputState.annualRatePct}% for ${inputState.termYears} ${s.years}',
                                        style: TextStyle(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.7))),
                                  ])),
                            ]),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(s.extraSection,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.bodyLg)),
                          const SizedBox(height: AppSpacing.md),
                          _field(s.extraMonthly, _extraMonthlyCtrl,
                              prefix: '\$', currency: true),
                          _field(s.extraAnnual, _extraAnnualCtrl,
                              prefix: '\$', currency: true),
                          _field(s.lumpSum, _lumpSumCtrl,
                              prefix: '\$', currency: true),
                          _field(s.lumpSumMonth, _lumpMonthCtrl),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _calculate(inputState),
                              style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.all(AppSpacing.lg)),
                              child: Text(s.calcSavings,
                                  style: const TextStyle(
                                      fontSize: AppTextSize.bodyLg)),
                            ),
                          ),
                          // Big CTA
                          if ((extraMonthly > 0 || extraAnnual > 0 || lumpSum > 0) && r != null) ...[
                            const SizedBox(height: AppSpacing.xl),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  AppTheme.accentGood,
                                  AppTheme.accentGoodLight
                                ]),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl),
                              ),
                              child: Column(children: [
                                const Icon(Icons.savings,
                                    color: Colors.white, size: 36),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  '${s.youCouldSave} ${_fmt.format(r.interestSaved)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: AppTextSize.titleMd,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  '${s.byPaying} ${_fmt.format(extraMonthly)} ${s.extraPerMonth}',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: AppTextSize.body),
                                  textAlign: TextAlign.center,
                                ),
                              ]),
                            ),
                          ],
                          if (r != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xl)),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Column(children: [
                                  _ResultRow(
                                      s.originalPayoff,
                                      '${r.originalPayoffMonths} ${s.months}'
                                      ' (${r.originalPayoffMonths ~/ 12} ${s.years})'),
                                  _ResultRow(
                                      s.newPayoff,
                                      '${r.newPayoffMonths} ${s.months}'
                                      ' (${r.newPayoffMonths ~/ 12} ${s.years})'),
                                  _ResultRow(s.timeSaved,
                                      '${r.yearsSaved} ${s.years} ${r.remMonthsSaved} ${s.months}',
                                      color: AppTheme.accentGood),
                                  const Divider(height: 24),
                                  _ResultRow(s.origTotalInt,
                                      _fmt.format(r.originalTotalInterest)),
                                  _ResultRow(s.newTotalInt,
                                      _fmt.format(r.newTotalInterest)),
                                  _ResultRow(s.interestSavedRow,
                                      _fmt.format(r.interestSaved),
                                      color: AppTheme.accentGood, bold: true),
                                ]),
                              ),
                            ),
                            if (extraMonthly > 0 || extraAnnual > 0 || lumpSum > 0) ...[
                              const SizedBox(height: AppSpacing.lg),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final text = isEs
                                        ? '💰 Pagos Extra\n'
                                          'Ahorro en intereses: ${_fmt.format(r.interestSaved)}\n'
                                          'Tiempo ahorrado: ${r.yearsSaved} ${s.years} ${r.remMonthsSaved} ${s.months}\n'
                                          '— MortgageUS'
                                        : '💰 Extra Payments\n'
                                          'Interest saved: ${_fmt.format(r.interestSaved)}\n'
                                          'Time saved: ${r.yearsSaved} ${s.years} ${r.remMonthsSaved} ${s.months}\n'
                                          '— MortgageUS';
                                    await Share.share(text);
                                  },
                                  icon: const Icon(Icons.share_rounded),
                                  label: Text(isEs ? 'Compartir resultados' : 'Share results'),
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 80),
                        ]),
                  ),
                ),
              )),
              const CalcwiseAdFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix, String? suffix, bool currency = false}) {
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
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  final bool bold;
  const _ResultRow(this.label, this.value, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: AppTheme.labelGray)),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color,
              )),
        ]),
      );
}

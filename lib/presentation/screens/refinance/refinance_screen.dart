import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../domain/models/refinance_result.dart';
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/save_scenario_button.dart';
import '../history/history_screen.dart' show HistoryScreen;

class RefinanceScreen extends StatefulWidget {
  const RefinanceScreen({super.key});
  @override
  State<RefinanceScreen> createState() => _RefinanceScreenState();
}

class _RefinanceScreenState extends State<RefinanceScreen> with CalcwiseAutoCalcMixin {
  final _formKey = GlobalKey<FormState>();
  final _balanceCtrl = TextEditingController(text: '300000');
  final _curRateCtrl = TextEditingController(text: '7.0');
  final _curYearsCtrl = TextEditingController(text: '25');
  final _newRateCtrl = TextEditingController(text: '6.0');
  final _newYearsCtrl = TextEditingController(text: '30');
  final _closingCtrl = TextEditingController(text: '4000');

  RefinanceResult? _result;
  String? _balanceError;

  bool _interacted = false;

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('refinance');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recalculate();
    });
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'refinance');
    _balanceCtrl.dispose();
    _curRateCtrl.dispose();
    _curYearsCtrl.dispose();
    _newRateCtrl.dispose();
    _newYearsCtrl.dispose();
    _closingCtrl.dispose();
    super.dispose();
  }

  void _recalculate() {
    final balance = double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0;
    final curRate = double.tryParse(_curRateCtrl.text) ?? 0;
    final curYears = int.tryParse(_curYearsCtrl.text) ?? 25;
    final newRate = double.tryParse(_newRateCtrl.text) ?? 0;
    final newYears = int.tryParse(_newYearsCtrl.text) ?? 30;
    final closing =
        double.tryParse(_closingCtrl.text.replaceAll(',', '')) ?? 4000;
    if (balance <= 0 || curYears <= 0 || newYears <= 0) {
      setState(() =>
          _balanceError = balance <= 0
              ? (isSpanishNotifier.value ? 'Ingresa un saldo válido' : 'Enter a valid loan balance')
              : null);
      return;
    }
    AnalyticsService.instance.maybeLogFirstCalculate();
    setState(() {
      _balanceError = null;
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
    // SmartHistory auto-save
    final r = _result;
    if (r != null && balance > 0) {
      final hash = ResultHasher.hashMixed({
        'balance': _roundTo(balance, 5000),
        'cur_rate': _roundTo(curRate, 0.25),
        'new_rate': _roundTo(newRate, 0.25),
        'closing': _roundTo(closing, 500),
      });
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'refinance',
        inputHash: hash,
        l1: {
          'balance': balance,
          'current_rate': curRate,
          'new_rate': newRate,
          'monthly_savings': r.monthlySavings,
          'break_even_months': r.breakEvenMonths,
        },
        l2: {
          'inputs': {
            'current_balance': balance,
            'current_rate': curRate,
            'current_years': curYears,
            'new_rate': newRate,
            'new_years': newYears,
            'closing_costs': closing,
          },
          'results': {
            'current_payment': r.oldMonthlyPayment,
            'new_payment': r.newMonthlyPayment,
            'monthly_savings': r.monthlySavings,
            'break_even_months': r.breakEvenMonths,
            'total_savings': r.totalSavingsOverLife,
          },
        },
      );
      HistoryScreen.refreshNotifier.value++;
      adService.onSave();
    }
  }

  Future<void> _exportPdf(bool isEs) async {
    final r = _result;
    if (r == null) return;
    final balance =
        double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0;
    final curRate = double.tryParse(_curRateCtrl.text) ?? 0;
    final curYears = int.tryParse(_curYearsCtrl.text) ?? 25;
    final newRate = double.tryParse(_newRateCtrl.text) ?? 0;
    final newYears = int.tryParse(_newYearsCtrl.text) ?? 30;
    final closing =
        double.tryParse(_closingCtrl.text.replaceAll(',', '')) ?? 4000;
    try {
      await PdfExportService.exportRefinance(
        context,
        balance: balance,
        curRate: curRate,
        curYears: curYears,
        newRate: newRate,
        newYears: newYears,
        closing: closing,
        result: r,
        isEs: isEs,
      );
      AnalyticsService.instance.logPdfExported();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isEs ? 'Error al exportar PDF' : 'Export failed'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final balance = double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0;
    final curRate = double.tryParse(_curRateCtrl.text) ?? 0;
    final newRate = double.tryParse(_newRateCtrl.text) ?? 0;
    final closing = double.tryParse(_closingCtrl.text.replaceAll(',', '')) ?? 4000;
    final curYears = int.tryParse(_curYearsCtrl.text) ?? 25;
    final newYears = int.tryParse(_newYearsCtrl.text) ?? 30;
    final hash = ResultHasher.hashMixed({
      'balance': _roundTo(balance, 5000),
      'cur_rate': _roundTo(curRate, 0.25),
      'new_rate': _roundTo(newRate, 0.25),
      'closing': _roundTo(closing, 500),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'refinance',
      inputHash: hash,
      l1: {
        'balance': balance,
        'current_rate': curRate,
        'new_rate': newRate,
        'monthly_savings': r.monthlySavings,
        'break_even_months': r.breakEvenMonths,
      },
      l2: {
        'inputs': {
          'current_balance': balance,
          'current_rate': curRate,
          'current_years': curYears,
          'new_rate': newRate,
          'new_years': newYears,
          'closing_costs': closing,
        },
        'results': {
          'current_payment': r.oldMonthlyPayment,
          'new_payment': r.newMonthlyPayment,
          'monthly_savings': r.monthlySavings,
          'break_even_months': r.breakEvenMonths,
          'total_savings': r.totalSavingsOverLife,
        },
      },
      label: label,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  void _onChanged() {
    scheduleCalc(_recalculate);
    if (_interacted) return;
    _interacted = true;
    _trackInteraction();
  }

  Future<void> _trackInteraction() async {
    adService.onAction();
    AnalyticsService.instance.logRefinanceSimulated();
    if (!mounted) return;
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
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
                  child: CalcwisePageEntrance(child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Form(
                              key: _formKey,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Section(s.currentLoan, [
                                      _field(s.currentBalance, _balanceCtrl,
                                          prefix: '\$',
                                          currency: true,
                                          errorText: _balanceError,
                                          required: true,
                                          onChanged: _onChanged),
                                      _field(s.currentRate, _curRateCtrl,
                                          suffix: '%',
                                          required: true,
                                          onChanged: _onChanged),
                                      _field(s.yearsRemaining, _curYearsCtrl,
                                          suffix: s.years as String?,
                                          required: true,
                                          onChanged: _onChanged),
                                    ]),
                                    const SizedBox(height: AppSpacing.lg),
                                    _Section(s.newLoan, [
                                      _field(s.newRate, _newRateCtrl,
                                          suffix: '%',
                                          required: true,
                                          onChanged: _onChanged),
                                      _field(s.newTerm, _newYearsCtrl,
                                          suffix: s.years as String?,
                                          required: true,
                                          onChanged: _onChanged),
                                      _field(s.closingCosts, _closingCtrl,
                                          prefix: '\$',
                                          currency: true,
                                          onChanged: _onChanged),
                                    ]),
                                    const SizedBox(height: AppSpacing.lg),
                                    if (r != null) ...[
                                      const SizedBox(height: AppSpacing.xl),
                                      Card(
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.xl)),
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                              AppSpacing.lg),
                                          child: Column(children: [
                                            _ResultRow(
                                                s.currentPayment,
                                                AmountFormatter.ui(
                                                    r.oldMonthlyPayment, 'USD')),
                                            _ResultRow(
                                                s.newPayment,
                                                AmountFormatter.ui(
                                                    r.newMonthlyPayment, 'USD')),
                                            _ResultRow(s.monthlySavings,
                                                AmountFormatter.ui(r.monthlySavings, 'USD'),
                                                color: r.monthlySavings > 0
                                                    ? AppTheme.accentGood
                                                    : CalcwiseSemanticColors
                                                        .error(Theme.of(context)
                                                            .brightness)),
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
                                                            ' (${(r.breakEvenMonths / 12).toStringAsFixed(1)} ${s.years})'),
                                            _ResultRow(
                                                s.totalSavings,
                                                AmountFormatter.ui(
                                                    r.totalSavingsOverLife, 'USD'),
                                                color:
                                                    r.totalSavingsOverLife > 0
                                                        ? AppTheme.accentGood
                                                        : CalcwiseSemanticColors
                                                            .error(Theme.of(
                                                                    context)
                                                                .brightness)),
                                            const SizedBox(
                                                height: AppSpacing.md),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(
                                                  AppSpacing.md),
                                              decoration: BoxDecoration(
                                                color: r.refinanceMakesSense
                                                    ? AppTheme.accentGood
                                                        .withValues(alpha: 0.1)
                                                    : CalcwiseSemanticColors
                                                        .errorBg,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppRadius.lg),
                                                border: Border.all(
                                                    color: r.refinanceMakesSense
                                                        ? AppTheme.accentGood
                                                        : CalcwiseSemanticColors
                                                            .errorDark),
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
                                                      : CalcwiseSemanticColors
                                                          .errorDark,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ]),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      SaveScenarioButton(onSave: _saveScenario, labelEn: 'Save Refinance', labelEs: 'Guardar refinanciamiento'),
                                      const SizedBox(height: AppSpacing.md),
                                      Row(children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              HapticFeedback.mediumImpact();
                                              final text = isEs
                                                  ? '📊 Refinanciamiento\n'
                                                      'Pago actual: ${AmountFormatter.ui(r!.oldMonthlyPayment, 'USD')}/mes\n'
                                                      'Nuevo pago: ${AmountFormatter.ui(r!.newMonthlyPayment, 'USD')}/mes\n'
                                                      'Ahorro mensual: ${AmountFormatter.ui(r!.monthlySavings, 'USD')}\n'
                                                      '— MortgageUS'
                                                  : '📊 Refinance Summary\n'
                                                      'Current payment: ${AmountFormatter.ui(r!.oldMonthlyPayment, 'USD')}/mo\n'
                                                      'New payment: ${AmountFormatter.ui(r!.newMonthlyPayment, 'USD')}/mo\n'
                                                      'Monthly savings: ${AmountFormatter.ui(r!.monthlySavings, 'USD')}\n'
                                                      '— MortgageUS';
                                              await Share.share(text);
                                            },
                                            icon:
                                                const Icon(Icons.share_rounded),
                                            label: Text(
                                                isEs ? 'Compartir' : 'Share'),
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: AppSpacing.sm),
                                      ValueListenableBuilder<bool>(
                                        valueListenable:
                                            freemiumService.hasFullAccessNotifier,
                                        builder: (context, isPremium, _) =>
                                            SizedBox(
                                          width: double.infinity,
                                          child: TextButton.icon(
                                            onPressed: () {
                                              HapticFeedback.mediumImpact();
                                              if (isPremium) {
                                                _exportPdf(isEs);
                                              } else {
                                                PaywallHard.show(context);
                                              }
                                            },
                                            icon: Icon(
                                                isPremium
                                                    ? Icons.picture_as_pdf_rounded
                                                    : Icons.lock_outline,
                                                size: 18),
                                            label: Text(
                                              isPremium
                                                  ? (isEs
                                                      ? 'Exportar PDF'
                                                      : 'Export PDF')
                                                  : (isEs
                                                      ? 'Exportar PDF — Premium'
                                                      : 'Export PDF — Premium'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            style: TextButton.styleFrom(
                                              minimumSize:
                                                  const Size(0, 44),
                                              foregroundColor: isPremium
                                                  ? AppTheme.primary
                                                  : AppTheme.secondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(
                                        height: AppSpacing.listBottomInset),
                                  ]),
                            ), // Form closes
                          ))))),
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
      bool required = false,
      VoidCallback? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: currency ? [CurrencyInputFormatter()] : null,
        onChanged: onChanged != null ? (_) => onChanged() : null,
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
          final es = isSpanishNotifier.value;
          if (raw.isEmpty) return required ? (es ? 'Requerido' : 'Required') : null;
          final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
          if (cleaned.isEmpty) return es ? 'Inválido' : 'Invalid';
          final n = double.tryParse(cleaned);
          if (n == null) return es ? 'Inválido' : 'Invalid';
          if (n < 0) return es ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
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
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Flexible(
            child: Text(label,
                style: const TextStyle(color: AppTheme.labelGray)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

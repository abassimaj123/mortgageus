import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../domain/models/arm_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show isSpanishNotifier, paywallSession, smartHistoryService;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../widgets/save_scenario_button.dart';
import '../../../core/services/pdf_export_service.dart';

class ArmScreen extends ConsumerStatefulWidget {
  const ArmScreen({super.key});
  @override
  ConsumerState<ArmScreen> createState() => _ArmScreenState();
}

class _ArmScreenState extends ConsumerState<ArmScreen> with CalcwiseAutoCalcMixin {
  final _loanCtrl = TextEditingController();
  final _initRateCtrl = TextEditingController(text: '6.0');
  final _adjRateCtrl = TextEditingController(text: '7.5');
  int _fixedYears = 5;
  int _termYears = 30;
  ARMResult? _result;
  String? _loanError;
  bool _logged = false;

  double _roundTo(double v, double step) => (v / step).round() * step;

  Future<void> _onInteraction() async {
    if (_logged) return;
    _logged = true;
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  static const _fixedOptions = [5, 7, 10];
  static const _termOptions = [15, 20, 30];

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('arm');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final input = ref.read(mortgageInputProvider);
      final loan =
          input.homePrice - (input.homePrice * input.downPaymentPct / 100.0);
      if (loan > 0) {
        _loanCtrl.text = loan.toStringAsFixed(0);
      }
      // Sync initial rate from main calculator
      if (input.annualRatePct > 0) {
        _initRateCtrl.text = input.annualRatePct.toStringAsFixed(2);
      }
      if (mounted) _calculate();
    });
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'arm');
    _loanCtrl.dispose();
    _initRateCtrl.dispose();
    _adjRateCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    unawaited(AnalyticsService.instance.maybeLogFirstCalculate());
    final loan = double.tryParse(_loanCtrl.text.replaceAll(',', '')) ?? 0;
    final initRate = double.tryParse(_initRateCtrl.text) ?? 0;
    final adjRate = double.tryParse(_adjRateCtrl.text) ?? 0;

    if (loan <= 0) {
      setState(() => _loanError = isSpanishNotifier.value
          ? 'Ingresa un monto de préstamo válido'
          : 'Enter a valid loan amount');
      return;
    }
    setState(() => _loanError = null);

    try {
      final r = MortgageCalculator.calcARM(
        loanAmount: loan,
        initialRatePct: initRate,
        fixedYears: _fixedYears,
        adjustedRatePct: adjRate,
        totalTermYears: _termYears,
      );
      setState(() => _result = r);
      _onInteraction();
      // SmartHistory auto-save
      final hash = ResultHasher.hashMixed({
        'loan': _roundTo(loan, 5000),
        'init_rate': _roundTo(initRate, 0.25),
        'adj_rate': _roundTo(adjRate, 0.25),
        'fixed_years': _fixedYears.toDouble(),
      });
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'arm',
        inputHash: hash,
        l1: {
          'loan_amount': loan,
          'initial_rate': initRate,
          'adjusted_rate': adjRate,
          'payment_increase': r.payment2 - r.payment1,
          'worst_case': r.payment2,
        },
        l2: {
          'inputs': {
            'loan_amount': loan,
            'initial_rate': initRate,
            'adjusted_rate': adjRate,
            'fixed_years': _fixedYears,
            'term_years': _termYears,
          },
          'results': {
            'initial_payment': r.payment1,
            'adjusted_payment': r.payment2,
            'payment_jump': r.payment2 - r.payment1,
            'worst_case_payment': r.payment2,
          },
        },
      );
    } catch (_) {
      setState(() => _result = null);
    }
  }

  Future<void> _exportPdf(bool isEs) async {
    final r = _result;
    if (r == null) return;
    final loan = double.tryParse(_loanCtrl.text.replaceAll(',', '')) ?? 0;
    final initRate = double.tryParse(_initRateCtrl.text) ?? 0;
    final adjRate = double.tryParse(_adjRateCtrl.text) ?? 0;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportArm(
        context,
        loanAmount: loan,
        initialRatePct: initRate,
        fixedYears: _fixedYears,
        adjustedRatePct: adjRate,
        termYears: _termYears,
        result: r,
        isEs: isEs,
      );
    });
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final loan = double.tryParse(_loanCtrl.text.replaceAll(',', '')) ?? 0;
    final initRate = double.tryParse(_initRateCtrl.text) ?? 0;
    final adjRate = double.tryParse(_adjRateCtrl.text) ?? 0;
    final hash = ResultHasher.hashMixed({
      'loan': _roundTo(loan, 5000),
      'init_rate': _roundTo(initRate, 0.25),
      'adj_rate': _roundTo(adjRate, 0.25),
      'fixed_years': _fixedYears.toDouble(),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'arm',
      inputHash: hash,
      l1: {
        'loan_amount': loan,
        'initial_rate': initRate,
        'adjusted_rate': adjRate,
        'payment_increase': r.payment2 - r.payment1,
        'worst_case': r.payment2,
      },
      l2: {
        'inputs': {
          'loan_amount': loan,
          'initial_rate': initRate,
          'adjusted_rate': adjRate,
          'fixed_years': _fixedYears,
          'term_years': _termYears,
        },
        'results': {
          'initial_payment': r.payment1,
          'adjusted_payment': r.payment2,
          'payment_jump': r.payment2 - r.payment1,
          'worst_case_payment': r.payment2,
        },
      },
      label: label,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        final r = _result;
        return Scaffold(
          appBar: AppBar(title: Text(s.toolArm)),
          body: CalcwisePageEntrance(child: Column(children: [
            Expanded(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Loan amount ───────────────────────────────────────
                    _field(
                      isEs ? 'Monto del Préstamo' : 'Loan Amount',
                      _loanCtrl,
                      prefix: '\$',
                      currency: true,
                      errorText: _loanError,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // ── Initial rate ──────────────────────────────────────
                    _field(
                      isEs ? 'Tasa Inicial (%)' : 'Initial Rate (%)',
                      _initRateCtrl,
                      suffix: '%',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // ── Fixed period chips ────────────────────────────────
                    Text(
                      isEs ? 'Período Fijo' : 'Fixed Period',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                        children: _fixedOptions.map((y) {
                      final sel = _fixedYears == y;
                      return Expanded(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Semantics(
                          label:
                              '$y year fixed period, ${sel ? "selected" : "not selected"}',
                          child: ChoiceChip(
                            label: Text('${y}yr'),
                            selected: sel,
                            selectedColor: AppTheme.primary,
                            showCheckmark: false,
                            labelStyle: TextStyle(
                              color: sel ? Colors.white : null,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) {
                              setState(() => _fixedYears = y);
                              _calculate();
                            },
                          ),
                        ),
                      ));
                    }).toList()),
                    const SizedBox(height: AppSpacing.md),
                    // ── Adjusted rate ─────────────────────────────────────
                    _field(
                      isEs
                          ? 'Tasa Ajustada después del reset (%)'
                          : 'Adjusted Rate after reset (%)',
                      _adjRateCtrl,
                      suffix: '%',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // ── Total term ────────────────────────────────────────
                    Text(
                      isEs ? 'Plazo Total' : 'Total Term',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                        children: _termOptions.map((y) {
                      final sel = _termYears == y;
                      return Expanded(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Semantics(
                          label:
                              '$y year total term, ${sel ? "selected" : "not selected"}',
                          child: ChoiceChip(
                            label: Text('${y}yr'),
                            selected: sel,
                            selectedColor: AppTheme.primary,
                            showCheckmark: false,
                            labelStyle: TextStyle(
                              color: sel ? Colors.white : null,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) {
                              setState(() => _termYears = y);
                              _calculate();
                            },
                          ),
                        ),
                      ));
                    }).toList()),
                    const SizedBox(height: AppSpacing.xl),
                    // ── Info note ─────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        isEs
                            ? 'Una ARM tiene una tasa fija inicial, luego se ajusta. Compara tu pago mensual inicial vs. después del reset.'
                            : 'An ARM has a fixed initial rate, then adjusts. Compare your monthly payment before and after the rate reset.',
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          color: AppTheme.primary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // ── Results ───────────────────────────────────────────
                    if (r != null) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      _ResultCard(
                          r: r,
                          s: s,
                          isEs: isEs,
                          fixedYears: _fixedYears,
                          termYears: _termYears),
                      const SizedBox(height: AppSpacing.md),
                      SaveScenarioButton(onSave: _saveScenario, labelEn: 'Save ARM Result', labelEs: 'Guardar resultado ARM'),
                      const SizedBox(height: AppSpacing.sm),
                      ValueListenableBuilder<bool>(
                        valueListenable:
                            freemiumService.hasFullAccessNotifier,
                        builder: (context, hasFull, _) => SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _exportPdf(isEs),
                            icon: const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 18),
                            label: Text(
                                isEs ? 'Exportar PDF' : 'Export PDF'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(
                                  color: AppTheme.primary),
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.mdPlus),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppRadius.mdPlus)),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: AppSpacing.xxl),
                      Center(
                        child: Text(
                          isEs
                              ? 'Ingresa un monto de préstamo para ver los resultados'
                              : 'Enter a loan amount to see results',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.labelGray,
                              fontSize: AppTextSize.md),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.listBottomInset),
                  ]),
            )),
            const CalcwiseAdFooter(),
          ])),
        );
      },
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    String? suffix,
    bool currency = false,
    String? errorText,
  }) {
    return TextFormField(
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
      onChanged: (_) => scheduleCalc(_calculate),
    );
  }
}

// ── Result card ───────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final ARMResult r;
  final AppStrings s;
  final bool isEs;
  final int fixedYears;
  final int termYears;
  const _ResultCard({
    required this.r,
    required this.s,
    required this.isEs,
    required this.fixedYears,
    required this.termYears,
  });

  @override
  Widget build(BuildContext context) {
    final interestDiff = r.totalInterest - r.fixedTotalInterest;
    final armCheaper = interestDiff < 0;

    return Column(children: [
      // ── Phase payments ────────────────────────────────────────────
      Row(children: [
        Expanded(
            child: _PhaseCard(
          label: isEs
              ? 'Pago durante\nperíodo fijo'
              : 'Payment during\nfixed period',
          sublabel: '${fixedYears}yr @ ${s.armMode}',
          value: AmountFormatter.ui(r.payment1, 'USD'),
          color: AppTheme.primary,
        )),
        const SizedBox(width: AppSpacing.md),
        Expanded(
            child: _PhaseCard(
          label: isEs ? 'Pago después\ndel reset' : 'Payment after\nreset',
          sublabel: isEs
              ? 'años ${fixedYears + 1}–$termYears'
              : 'yr ${fixedYears + 1}–$termYears',
          value: AmountFormatter.ui(r.payment2, 'USD'),
          color: r.payment2 > r.payment1
              ? AppTheme.accentWarn
              : AppTheme.accentGood,
        )),
      ]),
      const SizedBox(height: AppSpacing.lg),
      // ── Detail card ───────────────────────────────────────────────
      Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(children: [
            _Row(
              isEs ? 'Saldo al reset' : 'Balance at reset',
              AmountFormatter.ui(r.balanceAtReset, 'USD'),
            ),
            const Divider(height: 20),
            _Row(s.armTotalInterest, AmountFormatter.ui(r.totalInterest, 'USD')),
            _Row(
              isEs
                  ? 'Interés (tasa fija equivalente)'
                  : 'Interest (equivalent fixed rate)',
              AmountFormatter.ui(r.fixedTotalInterest, 'USD'),
            ),
            _Row(
              isEs ? 'Diferencia vs. fija' : 'Difference vs. fixed',
              '${armCheaper ? "-" : "+"}${AmountFormatter.ui(interestDiff.abs(), 'USD')}',
              color: armCheaper ? AppTheme.accentGood : AppTheme.accentWarn,
              bold: true,
            ),
            const Divider(height: 20),
            // Break-even
            if (r.breakEvenMonths == null)
              _breakEvenBanner(
                isEs ? s.armAlwaysBetter : s.armAlwaysBetter,
                AppTheme.accentGood,
              )
            else
              _breakEvenBanner(
                isEs
                    ? '${s.armCrossesAt} ${r.breakEvenMonths} (${(r.breakEvenMonths! / 12).toStringAsFixed(1)} ${s.years})'
                    : '${s.armCrossesAt} ${r.breakEvenMonths} (${(r.breakEvenMonths! / 12).toStringAsFixed(1)} ${s.years})',
                AppTheme.accentWarn,
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _breakEvenBanner(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.md)),
      );
}

class _PhaseCard extends StatelessWidget {
  final String label, sublabel, value;
  final Color color;
  const _PhaseCard({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontSize: AppTextSize.xs,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.xs),
          Text(sublabel,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: color.withValues(alpha: 0.7), fontSize: AppTextSize.xs)),
          const SizedBox(height: AppSpacing.sm),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.subtitle)),
        ]),
      );
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const _Row(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppTheme.labelGray, fontSize: AppTextSize.md))),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color,
                fontSize: AppTextSize.md,
              )),
        ]),
      );
}

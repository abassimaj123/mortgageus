import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/models/arm_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../domain/models/mortgage_result.dart';
import '../../providers/mortgage_providers.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../history/history_screen.dart';
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier, smartHistoryService;
import '../../widgets/save_scenario_button.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';

class ComparatorScreen extends ConsumerStatefulWidget {
  const ComparatorScreen({super.key});

  @override
  ConsumerState<ComparatorScreen> createState() => _ComparatorScreenState();
}

class _ComparatorScreenState extends ConsumerState<ComparatorScreen> {
  bool _isSaving = false;
  bool _armMode = false;
  int _fixedYears = 5;
  final _armRateCtrl = TextEditingController(text: '7.5');
  String? _lastAutoSaveHash;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('comparator');
    AnalyticsService.instance.logComparatorUsed();
    AnalyticsService.instance.maybeLogFirstCalculate();
    // ARM adjusted-rate field is reactive (calcArm runs in build) —
    // trigger a rebuild whenever the user types a new rate.
    _armRateCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'comparator');
    _armRateCtrl.dispose();
    super.dispose();
  }

  void _scheduleAutoSaveIfNeeded(
    MortgageInputState s,
    MortgageResult r30,
    MortgageResult r15,
  ) {
    final hash = ResultHasher.hashMixed({
      'home': ResultHasher.roundTo(s.homePrice, 1000),
      'down': ResultHasher.roundTo(s.downPaymentPct, 0.5),
      'rate': ResultHasher.roundTo(s.annualRatePct, 0.1),
    });
    if (hash == _lastAutoSaveHash) return;
    _lastAutoSaveHash = hash;
    final loan = s.homePrice - s.downPaymentDollar;
    smartHistoryService.scheduleAutoSave(
      appKey: 'mortgageus',
      screenId: 'comparator',
      inputHash: hash,
      l1: {
        'home_price': s.homePrice,
        'rate': s.annualRatePct,
        'monthly_15': r15.monthly.pitiPayment,
        'monthly_30': r30.monthly.pitiPayment,
        'monthly_diff': r15.monthly.pitiPayment - r30.monthly.pitiPayment,
        'interest_savings': r30.totalInterest - r15.totalInterest,
      },
      l2: {
        'inputs': {
          'home_price': s.homePrice,
          'down_percent': s.downPaymentPct,
          'annual_rate': s.annualRatePct,
          'loan_amount': loan,
        },
        'results': {
          'monthly_piti_30': r30.monthly.pitiPayment,
          'monthly_piti_15': r15.monthly.pitiPayment,
          'total_interest_30': r30.totalInterest,
          'total_interest_15': r15.totalInterest,
          'interest_saved_15yr': r30.totalInterest - r15.totalInterest,
          'payoff_30': '${r30.payoffDate.month}/${r30.payoffDate.year}',
          'payoff_15': '${r15.payoffDate.month}/${r15.payoffDate.year}',
        },
      },
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
  }

  Future<void> _saveComparison(
    BuildContext context,
    MortgageInputState s,
    MortgageResult r30,
    MortgageResult r15,
    bool isEs,
  ) async {
    HapticFeedback.mediumImpact();
    if (!freemiumService.hasFullAccess) {
      PaywallSoft.show(context);
      return;
    }
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);

    final comparisonId = DateTime.now().toIso8601String();

    Map<String, dynamic> buildRow(MortgageResult r, int termYears) => {
          'home_price': s.homePrice,
          'down_percent': s.downPaymentPct,
          'annual_rate': s.annualRatePct,
          'monthly_payment': r.monthly.pitiPayment,
          'total_interest': r.totalInterest,
          'loan_amount': s.homePrice - s.downPaymentDollar,
          'loan_type': s.loanType.label,
          'term_years': termYears,
          'tax_rate': s.propertyTaxRatePct,
          'insurance': s.homeInsuranceAnnual,
          'hoa': s.hoaMonthly,
          'created_at': comparisonId,
          'comparison_id': comparisonId,
        };

    await DatabaseHelper.instance.insertHistory(buildRow(r30, 30));
    await DatabaseHelper.instance.insertHistory(buildRow(r15, 15));

    HistoryScreen.refreshNotifier.value++;
    adService.onAction();

    if (!mounted) return;
    setState(() => _isSaving = false);
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.compare_arrows, size: 18, color: Colors.white),
        const SizedBox(width: AppSpacing.sm),
        Text(isEs
            ? 'Comparación guardada en historial'
            : 'Comparison saved to history'),
      ]),
      backgroundColor: AppTheme.primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _saveScenario(String? label) async {
    HapticFeedback.mediumImpact();
    final inputState = ref.read(mortgageInputProvider);
    final loan = inputState.homePrice - inputState.downPaymentDollar;
    if (loan <= 0 || inputState.homePrice <= 0) return;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month + 1);
    MortgageResult? calcResult(int termYears) {
      try {
        return MortgageCalculator.calculate(MortgageInput(
          homePrice: inputState.homePrice,
          downPayment: inputState.downPaymentDollar,
          annualRatePct: inputState.annualRatePct,
          termYears: termYears,
          loanType: inputState.loanType,
          propertyTaxRatePct: inputState.propertyTaxRatePct,
          homeInsuranceAnnual: inputState.homeInsuranceAnnual,
          hoaMonthly: inputState.hoaMonthly,
          pmiAnnualRatePct: 0.0,
          startDate: startDate,
        ));
      } catch (_) {
        return null;
      }
    }
    final r30 = calcResult(30);
    final r15 = calcResult(15);
    final hash = ResultHasher.hashMixed({
      'home': ResultHasher.roundTo(inputState.homePrice, 1000),
      'down': ResultHasher.roundTo(inputState.downPaymentPct, 0.5),
      'rate': ResultHasher.roundTo(inputState.annualRatePct, 0.1),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'comparator',
      inputHash: hash,
      l1: {
        'home_price': inputState.homePrice,
        'rate': inputState.annualRatePct,
        'monthly_15': r15?.monthly.pitiPayment,
        'monthly_30': r30?.monthly.pitiPayment,
        'savings': (r30 != null && r15 != null)
            ? r30.totalInterest - r15.totalInterest
            : null,
      },
      l2: {
        'inputs': {
          'home_price': inputState.homePrice,
          'down_percent': inputState.downPaymentPct,
          'annual_rate': inputState.annualRatePct,
          'loan_amount': loan,
        },
        'results': {
          'payments_15': r15?.monthly.pitiPayment,
          'payments_30': r30?.monthly.pitiPayment,
          'interest_diff_vs_30': (r30 != null && r15 != null)
              ? r30.totalInterest - r15.totalInterest
              : null,
        },
      },
      label: label,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mortgageInputProvider);


    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month + 1);
    final loan = s.homePrice - s.downPaymentDollar;

    MortgageResult? calc(int termYears) {
      if (s.homePrice <= 0 || loan < 0 || s.annualRatePct < 0) return null;
      final pmiRate = (s.homePrice > 0 &&
              (s.downPaymentDollar / s.homePrice) < 0.20 &&
              s.loanType != LoanType.va)
          ? MortgageConstants.pmiDefaultAnnualRate * 100
          : 0.0;
      try {
        return MortgageCalculator.calculate(MortgageInput(
          homePrice: s.homePrice,
          downPayment: s.downPaymentDollar,
          annualRatePct: s.annualRatePct,
          termYears: termYears,
          loanType: s.loanType,
          propertyTaxRatePct: s.propertyTaxRatePct,
          homeInsuranceAnnual: s.homeInsuranceAnnual,
          hoaMonthly: s.hoaMonthly,
          pmiAnnualRatePct: pmiRate,
          startDate: startDate,
        ));
      } catch (_) {
        return null;
      }
    }

    ARMResult? calcArm() {
      if (loan <= 0 || s.annualRatePct < 0) return null;
      final adjRate = double.tryParse(_armRateCtrl.text) ?? 7.5;
      try {
        return MortgageCalculator.calcARM(
          loanAmount: loan,
          initialRatePct: s.annualRatePct,
          fixedYears: _fixedYears,
          adjustedRatePct: adjRate,
          totalTermYears: 30,
        );
      } catch (_) {
        return null;
      }
    }

    final r30 = calc(30);
    final r15 = calc(15);
    final armRes = _armMode ? calcArm() : null;
    final canSave = !_armMode && r30 != null && r15 != null;

    if (!_armMode && r30 != null && r15 != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scheduleAutoSaveIfNeeded(s, r30, r15),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings str = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          appBar: AppBar(title: Text(str.comparatorTitle)),
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: CalcwisePageEntrance(child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header info
                      Semantics(
                        label: isEs
                            ? '${str.home} ${AmountFormatter.ui(s.homePrice, 'USD')}, ${str.down} ${AmountFormatter.ui(s.downPaymentDollar, 'USD')} (${s.downPaymentPct.toStringAsFixed(1)}%), ${str.rate} ${s.annualRatePct}%'
                            : '${str.home} ${AmountFormatter.ui(s.homePrice, 'USD')}, ${str.down} ${AmountFormatter.ui(s.downPaymentDollar, 'USD')} (${s.downPaymentPct.toStringAsFixed(1)}%), ${str.rate} ${s.annualRatePct}%',
                        child: Container(
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
                                  Text('${str.home} ${AmountFormatter.ui(s.homePrice, 'USD')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary)),
                                  Text(
                                      '${str.down} ${AmountFormatter.ui(s.downPaymentDollar, 'USD')}'
                                      ' (${s.downPaymentPct.toStringAsFixed(1)}%)'
                                      '  ${str.rate} ${s.annualRatePct}%',
                                      style: TextStyle(
                                          color: AppTheme.primary
                                              .withValues(alpha: 0.7),
                                          fontSize: AppTextSize.sm)),
                                ])),
                          ]),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Mode toggle
                      Row(children: [
                        Expanded(
                            child: _ModeToggleBtn(
                          label: str.standardMode,
                          icon: Icons.compare_arrows,
                          selected: !_armMode,
                          onTap: () => setState(() => _armMode = false),
                        )),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                            child: _ModeToggleBtn(
                          label: str.armMode,
                          icon: Icons.show_chart,
                          selected: _armMode,
                          onTap: () {
                            setState(() => _armMode = true);
                            AnalyticsService.instance.logArmCalculated();
                          },
                        )),
                      ]),
                      const SizedBox(height: AppSpacing.xl),
                      // Standard mode
                      if (!_armMode) ...[
                        Text(str.scenarioComp,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.subtitle)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(str.scenarioDesc,
                            style: TextStyle(
                                color: AppTheme.labelGray,
                                fontSize: AppTextSize.md)),
                        const SizedBox(height: AppSpacing.lg),
                        if (r30 == null || r15 == null)
                          Center(child: Text(str.enterValid))
                        else
                          _CompareTable(
                              r30: r30, r15: r15, s: str),
                      ],
                      // ARM mode
                      if (_armMode) ...[
                        _ArmControls(
                          fixedYears: _fixedYears,
                          rateCtrl: _armRateCtrl,
                          onFixedYearsChanged: (y) =>
                              setState(() => _fixedYears = y),
                          s: str,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (armRes == null)
                          Center(child: Text(str.enterValid))
                        else
                          _ArmCompareTable(
                            arm: armRes,
                            fixedYears: _fixedYears,
                            adjRate: double.tryParse(_armRateCtrl.text) ?? 7.5,
                            s: str,
                          ),
                      ],
                      if (canSave) ...[
                        const SizedBox(height: AppSpacing.xs),
                        ValueListenableBuilder<bool>(
                          valueListenable: freemiumService.hasFullAccessNotifier,
                          builder: (_, isPremium, __) =>
                              ValueListenableBuilder<bool>(
                            valueListenable: freemiumService.isRewardedNotifier,
                            builder: (_, isRewarded, __) {
                              final unlocked = isPremium || isRewarded;
                              return Semantics(
                                label: isEs
                                    ? 'Guardar comparación'
                                    : 'Save comparison',
                                button: true,
                                child: InkWell(
                                  onTap: _isSaving
                                      ? null
                                      : () => _saveComparison(
                                          context, s, r30, r15, isEs),
                                  borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.mdPlus),
                                    decoration: BoxDecoration(
                                      border:
                                          Border.all(color: AppTheme.primary),
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.mdPlus),
                                    ),
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _isSaving
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : Icon(
                                                  unlocked
                                                      ? Icons
                                                          .bookmark_add_rounded
                                                      : Icons.lock_outline,
                                                  color: AppTheme.primary,
                                                  size: 18),
                                          const SizedBox(width: AppSpacing.sm),
                                          Text(
                                              isEs
                                                  ? 'Guardar comparación'
                                                  : 'Save comparison',
                                              style: const TextStyle(
                                                  color: AppTheme.primary,
                                                  fontWeight: FontWeight.w600)),
                                        ]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (!_armMode && r30 != null && r15 != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SaveScenarioButton(onSave: _saveScenario, labelEn: 'Save Comparison', labelEs: 'Guardar comparación'),
                        const SizedBox(height: AppSpacing.sm),
                        ValueListenableBuilder<bool>(
                          valueListenable: freemiumService.hasFullAccessNotifier,
                          builder: (context, isPremium, _) {
                            return SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () async {
                                  HapticFeedback.mediumImpact();
                                  if (isPremium) {
                                    try {
                                      await PdfExportService.exportComparator(
                                          context, s, r30!, r15!,
                                          isEs: isEs);
                                      AnalyticsService.instance.logPdfExported();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(isEs
                                              ? 'PDF exportado con éxito'
                                              : 'PDF exported successfully'),
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 2),
                                        ));
                                      }
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(isEs
                                              ? 'Error al exportar PDF'
                                              : 'Export failed'),
                                          behavior: SnackBarBehavior.floating,
                                        ));
                                      }
                                    }
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
                                      ? (isEs ? 'Exportar PDF' : 'Export PDF')
                                      : (isEs
                                          ? 'Exportar PDF — Premium'
                                          : 'Export PDF — Premium'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  foregroundColor: isPremium
                                      ? AppTheme.primary
                                      : AppTheme.secondary,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ]),
              ),
            ),
          )),
        );
      },
    );
  }
}

class _CompareTable extends StatelessWidget {
  final MortgageResult r30, r15;
  final AppStrings s;
  const _CompareTable({
    required this.r30,
    required this.r15,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    // 15yr wins on interest; 30yr wins on monthly payment
    return Column(children: [
      // Column headers
      Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(flex: 4, child: _ScenarioHeader(s.yr30, AppTheme.primary)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(flex: 4, child: _ScenarioHeader(s.yr15, AppTheme.accentGood)),
      ]),
      const SizedBox(height: AppSpacing.md),
      _CompareRow(
        label: s.monthlyPILabel,
        val30: AmountFormatter.ui(r30.monthly.piPayment, 'USD'),
        val15: AmountFormatter.ui(r15.monthly.piPayment, 'USD'),
        winner: 30, // 30yr lower monthly
      ),
      _CompareRow(
        label: s.monthlyPITI,
        val30: AmountFormatter.ui(r30.monthly.pitiPayment, 'USD'),
        val15: AmountFormatter.ui(r15.monthly.pitiPayment, 'USD'),
        winner: 30,
      ),
      _CompareRow(
        label: s.totalInterest,
        val30: AmountFormatter.ui(r30.totalInterest, 'USD'),
        val15: AmountFormatter.ui(r15.totalInterest, 'USD'),
        winner: 15, // 15yr saves interest
      ),
      _CompareRow(
        label: s.totalCost,
        val30: AmountFormatter.ui(r30.totalCost, 'USD'),
        val15: AmountFormatter.ui(r15.totalCost, 'USD'),
        winner: 15,
      ),
      _CompareRow(
        label: s.payoffDate,
        val30: '${r30.payoffDate.month}/${r30.payoffDate.year}',
        val15: '${r15.payoffDate.month}/${r15.payoffDate.year}',
        winner: 15, // 15yr payoff sooner
      ),
      const SizedBox(height: AppSpacing.lg),
      // Savings callout
      Semantics(
        label:
            '15-year advantage: saves ${AmountFormatter.ui(r30.totalInterest - r15.totalInterest, 'USD')} in interest. '
            '30-year advantage: ${AmountFormatter.ui(r15.monthly.piPayment - r30.monthly.piPayment, 'USD')} lower monthly payment.',
        child: Card(
          color: AppTheme.accentGood.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(
                  color: AppTheme.accentGood.withValues(alpha: 0.4))),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.advantage15,
                  style: TextStyle(
                    color: AppTheme.accentGood,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyMd,
                  )),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  '${s.interestSaved} ${AmountFormatter.ui(r30.totalInterest - r15.totalInterest, 'USD')}',
                  style: const TextStyle(fontSize: AppTextSize.md)),
              Text(
                  '${s.paidOff15} ${(r30.payoffDate.year - r15.payoffDate.year)} ${s.yearsEarlier}',
                  style: const TextStyle(fontSize: AppTextSize.md)),
              const Divider(height: 20),
              Text(s.advantage30,
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyMd,
                  )),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  '${s.monthlySavings} ${AmountFormatter.ui(r15.monthly.piPayment - r30.monthly.piPayment, 'USD')} ${s.lower}',
                  style: const TextStyle(fontSize: AppTextSize.md)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _ScenarioHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _ScenarioHeader(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
        ),
        child: Text(label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: AppTextSize.body,
            )),
      );
}

class _CompareRow extends StatelessWidget {
  final String label, val30, val15;
  final int winner; // 30 or 15 = which scenario wins
  const _CompareRow({
    required this.label,
    required this.val30,
    required this.val15,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: TextStyle(
                      color: AppTheme.labelGray, fontSize: AppTextSize.md))),
          Expanded(
              flex: 4,
              child: _ValueCell(val30,
                  isWinner: winner == 30, color: AppTheme.primary)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              flex: 4,
              child: _ValueCell(val15,
                  isWinner: winner == 15, color: AppTheme.accentGood)),
        ]),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String value;
  final bool isWinner;
  final Color color;
  const _ValueCell(this.value, {required this.isWinner, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isWinner ? color.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:
              isWinner ? Border.all(color: color.withValues(alpha: 0.4)) : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (isWinner) ...[
            Icon(Icons.check_circle, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
              child: Text(value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
                    fontSize: AppTextSize.sm,
                    color: isWinner ? color : null,
                  ))),
        ]),
      );
}

// ── Mode toggle button ────────────────────────────────────────────────────────

class _ModeToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ModeToggleBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary
                  : CalcwiseTheme.of(context).surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
              border: selected
                  ? null
                  : Border.all(
                      color: AppTheme.labelGray.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AppTheme.labelGray),
              const SizedBox(width: AppRadius.sm),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTextSize.md,
                    color: selected ? Colors.white : AppTheme.labelGray,
                  )),
            ]),
          ),
        ),
      );
}

// ── ARM controls ──────────────────────────────────────────────────────────────

class _ArmControls extends StatelessWidget {
  final int fixedYears;
  final TextEditingController rateCtrl;
  final ValueChanged<int> onFixedYearsChanged;
  final AppStrings s;

  const _ArmControls({
    required this.fixedYears,
    required this.rateCtrl,
    required this.onFixedYearsChanged,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    const presets = [3, 5, 7, 10];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.armFixedPeriod,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: AppTextSize.body)),
      const SizedBox(height: AppSpacing.sm),
      Row(
          children: presets.map((y) {
        final sel = fixedYears == y;
        return Expanded(
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Semantics(
            label: '${y}/1 ARM${sel ? ', selected' : ''}',
            child: ChoiceChip(
              label: Text('${y}/1'),
              selected: sel,
              selectedColor: AppTheme.primary,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: sel ? Colors.white : null,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) => onFixedYearsChanged(y),
            ),
          ),
        ));
      }).toList()),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: rateCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: s.armAdjRate as String?,
          suffixText: '%',
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
        ),
      ),
    ]);
  }
}

// ── ARM compare table ─────────────────────────────────────────────────────────

class _ArmCompareTable extends StatelessWidget {
  final ARMResult arm;
  final int fixedYears;
  final double adjRate;
  final AppStrings s;

  const _ArmCompareTable({
    required this.arm,
    required this.fixedYears,
    required this.adjRate,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final armInterestSavings = arm.fixedTotalInterest - arm.totalInterest;
    final armIsCheaper = armInterestSavings > 0;

    return Column(children: [
      // Column headers
      Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(
            flex: 4, child: _ScenarioHeader('Fixed 30yr', AppTheme.primary)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            flex: 4,
            child: _ScenarioHeader('ARM ${fixedYears}/1', AppTheme.accentGood)),
      ]),
      const SizedBox(height: AppSpacing.md),
      _CompareRow(
        label: s.armPaymentDuring,
        val30: AmountFormatter.ui(arm.fixedPayment, 'USD'),
        val15: AmountFormatter.ui(arm.payment1, 'USD'),
        winner: arm.payment1 < arm.fixedPayment ? 15 : 30,
      ),
      _CompareRow(
        label: s.armPaymentAfter,
        val30: AmountFormatter.ui(arm.fixedPayment, 'USD'),
        val15: AmountFormatter.ui(arm.payment2, 'USD'),
        winner: arm.payment2 < arm.fixedPayment ? 15 : 30,
      ),
      _CompareRow(
        label: s.armTotalInterest,
        val30: AmountFormatter.ui(arm.fixedTotalInterest, 'USD'),
        val15: AmountFormatter.ui(arm.totalInterest, 'USD'),
        winner: armIsCheaper ? 15 : 30,
      ),
      _CompareRow(
        label: s.armTotalCost,
        val30: AmountFormatter.ui(
            (arm.totalCost - arm.totalInterest) + arm.fixedTotalInterest, 'USD'),
        val15: AmountFormatter.ui(arm.totalCost, 'USD'),
        winner: armIsCheaper ? 15 : 30,
      ),
      const SizedBox(height: AppSpacing.lg),
      Semantics(
        label: armIsCheaper
            ? 'ARM saves ${AmountFormatter.ui(armInterestSavings.abs(), 'USD')} in total interest vs fixed 30-year.'
            : 'ARM costs ${AmountFormatter.ui(armInterestSavings.abs(), 'USD')} more in total interest vs fixed 30-year.',
        child: Card(
          color: (armIsCheaper
                  ? AppTheme.accentGood
                  : CalcwiseSemanticColors.warnIcon)
              .withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(
                color: (armIsCheaper
                        ? AppTheme.accentGood
                        : CalcwiseSemanticColors.warnIcon)
                    .withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (armIsCheaper) ...[
                Text(
                  '${s.armTotalInterest}: ${AmountFormatter.ui(armInterestSavings.abs(), 'USD')} ${s.lower}',
                  style: TextStyle(
                      color: AppTheme.accentGood,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyMd),
                ),
                const SizedBox(height: AppRadius.sm),
                if (arm.breakEvenMonths == null)
                  Text(s.armAlwaysBetter,
                      style: TextStyle(
                          color: AppTheme.accentGood, fontSize: AppTextSize.md))
                else
                  Text(
                      '${s.armCrossesAt} ${arm.breakEvenMonths}'
                      ' (${(arm.breakEvenMonths! / 12).toStringAsFixed(1)} ${s.years})',
                      style: const TextStyle(fontSize: AppTextSize.md)),
              ] else ...[
                Text(
                  '${s.armTotalInterest}: ${AmountFormatter.ui(armInterestSavings.abs(), 'USD')} more vs fixed',
                  style: const TextStyle(
                      color: CalcwiseSemanticColors.warnIcon,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyMd),
                ),
                const SizedBox(height: AppRadius.sm),
                Text(
                  'Rate reset to ${adjRate.toStringAsFixed(2)}% increases long-term cost.',
                  style: const TextStyle(fontSize: AppTextSize.md),
                ),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
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
import '../history/history_screen.dart';
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier;
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

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logComparatorUsed();
  }

  @override
  void dispose() {
    _armRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveComparison(
    BuildContext context,
    MortgageInputState s,
    MortgageResult r30,
    MortgageResult r15,
    bool isEs,
  ) async {
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

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mortgageInputProvider);
    final fmt =
        NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
    final fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

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

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings str = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header info
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border.all(color: AppTheme.primary, width: 1),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Row(children: [
                          const Icon(Icons.home_rounded,
                              color: AppTheme.primary),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('${str.home} ${fmt.format(s.homePrice)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary)),
                                Text(
                                    '${str.down} ${fmt.format(s.downPaymentDollar)}'
                                    ' (${s.downPaymentPct.toStringAsFixed(1)}%)'
                                    '  ${str.rate} ${s.annualRatePct}%',
                                    style: TextStyle(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.7),
                                        fontSize: AppTextSize.sm)),
                              ])),
                        ]),
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
                          onTap: () async {
                            setState(() => _armMode = true);
                            AnalyticsService.instance.logArmCalculated();
                            final trigger = await paywallSession.recordAction();
                            if (trigger == PaywallTrigger.soft)
                              PaywallSoft.show(context);
                            if (trigger == PaywallTrigger.hard)
                              PaywallHard.show(context);
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
                              r30: r30, r15: r15, fmt: fmt, fmtK: fmtK, s: str),
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
                            fmt: fmt,
                            fmtK: fmtK,
                            s: str,
                          ),
                      ],
                      if (canSave) ...[
                        const SizedBox(height: AppSpacing.xs),
                        ValueListenableBuilder<bool>(
                          valueListenable: freemiumService.isPremiumNotifier,
                          builder: (_, isPremium, __) =>
                              ValueListenableBuilder<bool>(
                            valueListenable: freemiumService.isRewardedNotifier,
                            builder: (_, isRewarded, __) {
                              final unlocked = isPremium || isRewarded;
                              return GestureDetector(
                                onTap: _isSaving
                                    ? null
                                    : () => _saveComparison(
                                        context, s, r30, r15, isEs),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.mdPlus),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppTheme.primary),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.mdPlus),
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
                                                    ? Icons.bookmark_add_rounded
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
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompareTable extends StatelessWidget {
  final MortgageResult r30, r15;
  final NumberFormat fmt, fmtK;
  final AppStrings s;
  const _CompareTable({
    required this.r30,
    required this.r15,
    required this.fmt,
    required this.fmtK,
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
        val30: fmt.format(r30.monthly.piPayment),
        val15: fmt.format(r15.monthly.piPayment),
        winner: 30, // 30yr lower monthly
      ),
      _CompareRow(
        label: s.monthlyPITI,
        val30: fmt.format(r30.monthly.pitiPayment),
        val15: fmt.format(r15.monthly.pitiPayment),
        winner: 30,
      ),
      _CompareRow(
        label: s.totalInterest,
        val30: fmtK.format(r30.totalInterest),
        val15: fmtK.format(r15.totalInterest),
        winner: 15, // 15yr saves interest
      ),
      _CompareRow(
        label: s.totalCost,
        val30: fmtK.format(r30.totalCost),
        val15: fmtK.format(r15.totalCost),
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
      Card(
        color: AppTheme.accentGood.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side:
                BorderSide(color: AppTheme.accentGood.withValues(alpha: 0.4))),
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
                '${s.interestSaved} ${fmtK.format(r30.totalInterest - r15.totalInterest)}',
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
                '${s.monthlySavings} ${fmt.format(r15.monthly.piPayment - r30.monthly.piPayment)} ${s.lower}',
                style: const TextStyle(fontSize: AppTextSize.md)),
          ]),
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
    return Padding(
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
  Widget build(BuildContext context) => InkWell(
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
                : Border.all(color: AppTheme.labelGray.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 16, color: selected ? Colors.white : AppTheme.labelGray),
            const SizedBox(width: AppRadius.sm),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextSize.md,
                  color: selected ? Colors.white : AppTheme.labelGray,
                )),
          ]),
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
  final NumberFormat fmt;
  final NumberFormat fmtK;
  final AppStrings s;

  const _ArmCompareTable({
    required this.arm,
    required this.fixedYears,
    required this.adjRate,
    required this.fmt,
    required this.fmtK,
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
        val30: fmt.format(arm.fixedPayment),
        val15: fmt.format(arm.payment1),
        winner: arm.payment1 < arm.fixedPayment ? 15 : 30,
      ),
      _CompareRow(
        label: s.armPaymentAfter,
        val30: fmt.format(arm.fixedPayment),
        val15: fmt.format(arm.payment2),
        winner: arm.payment2 < arm.fixedPayment ? 15 : 30,
      ),
      _CompareRow(
        label: s.armTotalInterest,
        val30: fmtK.format(arm.fixedTotalInterest),
        val15: fmtK.format(arm.totalInterest),
        winner: armIsCheaper ? 15 : 30,
      ),
      _CompareRow(
        label: s.armTotalCost,
        val30: fmtK.format(
            (arm.totalCost - arm.totalInterest) + arm.fixedTotalInterest),
        val15: fmtK.format(arm.totalCost),
        winner: armIsCheaper ? 15 : 30,
      ),
      const SizedBox(height: AppSpacing.lg),
      Card(
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
                '${s.armTotalInterest}: ${fmtK.format(armInterestSavings.abs())} ${s.lower}',
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
                    ' (${(arm.breakEvenMonths! / 12).toStringAsFixed(1)} yrs)',
                    style: const TextStyle(fontSize: AppTextSize.md)),
            ] else ...[
              Text(
                '${s.armTotalInterest}: ${fmtK.format(armInterestSavings.abs())} more vs fixed',
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
    ]);
  }
}

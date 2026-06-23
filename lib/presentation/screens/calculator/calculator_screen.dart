import 'dart:async';
import 'dart:math' show pow;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/pdf_export_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/models/mortgage_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../providers/mortgage_providers.dart';
import '../history/history_screen.dart' show HistoryScreen;
import '../../../main.dart'
    show
        adService,
        paywallSession,
        isSpanishNotifier,
        preFillNotifier,
        smartHistoryService;
import '../../widgets/save_scenario_button.dart';
import '../../../core/services/analytics_service.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/info_tooltip.dart';
import '../../../core/utils/insight_engine.dart';
import '../../widgets/insight_card.dart';
import '../../widgets/paywall_hard.dart';

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});
  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _homePriceCtrl = TextEditingController(text: '400000');
  final _downPayCtrl = TextEditingController(text: '20');
  final _rateCtrl = TextEditingController(text: '6.8');
  final _taxCtrl = TextEditingController(text: '1.1');
  final _insuranceCtrl = TextEditingController(text: '1750');
  final _hoaCtrl = TextEditingController(text: '0');
  final _incomeCtrl = TextEditingController(text: '80000');
  double _monthlyIncome = 0.0;
  bool _advancedExpanded = false;
  String? _homePriceError;
  Timer? _autoSaveTimer;

  // Cached 15-yr comparison result — recomputed only when inputs change.
  MortgageResult? _insightResult15yr;
  String? _insightCacheKey;


  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('calculator');
    // Push controller defaults to provider on first frame so all tabs are in sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = ref.read(mortgageInputProvider.notifier);
      n.updateHomePrice(400000);
      n.updateDownPaymentPct(20);
      n.updateRate(6.8);
      n.updatePropertyTaxRate(1.1);
      n.updateHomeInsurance(1750);
      n.updateHoa(0);
    });
    preFillNotifier.addListener(_onPreFill);
  }

  void _onPreFill() {
    final data = preFillNotifier.value;
    if (data == null) return;
    preFillNotifier.value = null; // consume immediately to avoid loops

    final n = ref.read(mortgageInputProvider.notifier);

    if (data.containsKey('homePrice')) {
      final hp = data['homePrice']!;
      _homePriceCtrl.text = hp.toStringAsFixed(0);
      n.updateHomePrice(hp);
    }
    if (data.containsKey('downPayment')) {
      final dp = data['downPayment']!;
      final hp = data['homePrice'] ?? ref.read(mortgageInputProvider).homePrice;
      final pct = hp > 0 ? (dp / hp) * 100 : 20.0;
      _downPayCtrl.text = pct.toStringAsFixed(1);
      n.updateDownPaymentPct(pct);
    }
    if (data.containsKey('rate')) {
      final r = data['rate']!;
      _rateCtrl.text = r.toStringAsFixed(2);
      n.updateRate(r);
    }
    if (data.containsKey('termYears')) {
      n.updateTerm(data['termYears']!.toInt());
    }
    if (data.containsKey('taxRate')) {
      final tr = data['taxRate']!;
      _taxCtrl.text = tr.toStringAsFixed(2);
      n.updatePropertyTaxRate(tr);
    }
    if (data.containsKey('insurance')) {
      final ins = data['insurance']!;
      _insuranceCtrl.text = ins.toStringAsFixed(0);
      n.updateHomeInsurance(ins);
    }
    if (data.containsKey('hoa')) {
      final hoa = data['hoa']!;
      _hoaCtrl.text = hoa.toStringAsFixed(0);
      n.updateHoa(hoa);
    }
  }

  // ── SmartHistory: hash + payload helpers ──────────────────────────────────

  /// Deterministic input hash for dedup. Uses only key inputs (rounded).
  String? _currentHash() {
    final result = ref.read(mortgageResultProvider);
    if (result == null || result.loanAmount <= 0) return null;
    final inputState = ref.read(mortgageInputProvider);
    return ResultHasher.hashMixed({
      'home': ResultHasher.roundTo(inputState.homePrice, 1000),
      'down': ResultHasher.roundTo(inputState.downPaymentPct, 0.5),
      'rate': ResultHasher.roundTo(inputState.annualRatePct, 0.1),
      'term': inputState.termYears,
      'type': inputState.loanType.label,
    });
  }

  /// L2 payload — the full round-trippable record used to rebuild the row.
  /// Includes a 'tools' section when in-scenario tools have been calculated.
  Map<String, dynamic> _l2Payload(String label) {
    final result = ref.read(mortgageResultProvider)!;
    final inputState = ref.read(mortgageInputProvider);
    return {
      'inputs': {
        'home_price': inputState.homePrice,
        'down_percent': inputState.downPaymentPct,
        'annual_rate': inputState.annualRatePct,
        'term_years': inputState.termYears,
        'loan_type': inputState.loanType.label,
        'tax_rate': inputState.propertyTaxRatePct,
        'insurance': inputState.homeInsuranceAnnual,
        'hoa': inputState.hoaMonthly,
      },
      'results': {
        'monthly_payment': result.monthly.pitiPayment,
        'total_interest': result.totalInterest,
        'total_cost': result.totalCost,
        'loan_amount': result.loanAmount,
      },
    };
  }

  /// L1 payload — lightweight summary for list display.
  Map<String, dynamic> _l1Payload(String label) {
    final result = ref.read(mortgageResultProvider)!;
    final inputState = ref.read(mortgageInputProvider);
    return {
      'home_price': inputState.homePrice,
      'down_payment': inputState.downPaymentDollar,
      'rate': inputState.annualRatePct,
      'term': inputState.termYears,
      'monthly_payment': result.monthly.pitiPayment,
      'total_interest': result.totalInterest,
    };
  }

  String _autoLabel() {
    final inputState = ref.read(mortgageInputProvider);
    return '${inputState.homePrice ~/ 1000}K · ${inputState.annualRatePct.toStringAsFixed(2)}% · ${inputState.termYears}yr';
  }

  void _scheduleAutoSave() {
    final hash = _currentHash();
    if (hash == null) return;
    final label = _autoLabel();
    smartHistoryService.scheduleAutoSave(
      appKey: 'mortgageus',
      screenId: 'mortgage_calculator',
      inputHash: hash,
      l1: _l1Payload(label),
      l2: _l2Payload(label),
      // Refresh history tab AFTER the DB write — avoids race condition where
      // the history screen would query before the entry is persisted.
      onSaved: () {
        if (!mounted) return;
        HistoryScreen.refreshNotifier.value++;
      },
    );
    // Side-effects (ads, analytics, rate watch) fire after a short delay,
    // independent of the DB write timing.
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      adService.onSave();
      try {
        AnalyticsService.instance.logSave();
        AnalyticsService.instance.logHistorySaved();
        unawaited(AnalyticsService.instance.maybeLogFirstCalculate());
      } catch (_) {}
      final inputState = ref.read(mortgageInputProvider);
      final result = ref.read(mortgageResultProvider);
      unawaited(AnalyticsService.instance.logCalculation(
        homePrice: inputState.homePrice,
        downPct: inputState.downPaymentPct,
        ratePct: inputState.annualRatePct,
        amortYears: inputState.termYears,
      ));
      unawaited(RateWatchService.instance
          .checkRate(inputState.annualRatePct, appLabel: 'MortgageUS'));
      // Emotional trigger: accessible monthly payment → ask for review.
      if (result != null &&
          result.monthly.pitiPayment < 3000 &&
          result.monthly.pitiPayment > 0) {
        CalcwiseReviewService.instance.requestAfterPremium();
      }
    });
  }

  /// Save the current calculation as a pinned scenario (premium).
  Future<void> _saveScenario(String? label) async {
    final hash = _currentHash();
    if (hash == null) return;
    final effectiveLabel = (label != null && label.isNotEmpty)
        ? label
        : _autoLabel();
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'mortgage_calculator',
      inputHash: hash,
      l1: _l1Payload(effectiveLabel),
      l2: _l2Payload(effectiveLabel),
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
    try {
      AnalyticsService.instance.logSave();
      AnalyticsService.instance.logHistorySaved();
    } catch (_) {}
    if (!mounted) return;
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
    if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    smartHistoryService.cancelPendingSave('mortgageus', 'calculator');
    preFillNotifier.removeListener(_onPreFill);
    _homePriceCtrl.dispose();
    _downPayCtrl.dispose();
    _rateCtrl.dispose();
    _taxCtrl.dispose();
    _insuranceCtrl.dispose();
    _hoaCtrl.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(mortgageResultProvider);
    final inputState = ref.watch(mortgageInputProvider);
    final notifier = ref.read(mortgageInputProvider.notifier);

    // Auto-save: whenever a valid result is produced, schedule a debounced save.
    ref.listen<MortgageResult?>(mortgageResultProvider, (previous, next) {
      if (next != null && next.loanAmount > 0) {
        _scheduleAutoSave();
      }
    });

    // Recompute 15-yr cached result when inputs change (no-ops when key is same).
    if (result != null) _recompute15yr(inputState, result);

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                slivers: [
                  // ── Hero card ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: CalcwiseStaggerItem(
                      index: 0,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _HeroCard(result: result, s: s),
                      ),
                    ),
                  ),
                  // ── Inputs + actions ───────────────────────────────────
                  SliverToBoxAdapter(
                    child: CalcwiseStaggerItem(
                      index: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Home Price
                              _buildField(s.homePrice, _homePriceCtrl,
                                  prefix: '\$',
                                  required: true,
                                  currency: true,
                                  errorText: _homePriceError, onChanged: (v) {
                                final hp =
                                    double.tryParse(v.replaceAll(',', '')) ?? 0;
                                notifier.updateHomePrice(hp);
                                setState(() {
                                  _homePriceError = hp <= 0
                                      ? (isEs
                                          ? 'Ingresa un precio válido'
                                          : 'Enter a valid home price')
                                      : null;
                                });
                              }),
                              const SizedBox(height: AppSpacing.md),
                              // Down Payment row
                              _DownPaymentRow(
                                ctrl: _downPayCtrl,
                                notifier: notifier,
                                inputState: inputState,
                                s: s,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              // Interest Rate
                              _buildField(s.interestRate, _rateCtrl,
                                  suffix: '%',
                                  percent: true,
                                  required: true,
                                  helperText: isEs
                                      ? 'Tasa predeterminada de 2026 — actualiza con tu tasa real'
                                      : 'Default rate as of 2026 — update to your actual rate',
                                  onChanged: (v) => notifier.updateRate(
                                      double.tryParse(v.replaceAll(',', '.')) ??
                                          6.8)),
                              const SizedBox(height: AppSpacing.md),
                              // Term chips
                              _TermSelector(
                                  inputState: inputState,
                                  notifier: notifier,
                                  s: s,
                                  onEdit: () {}),
                              const SizedBox(height: AppSpacing.md),
                              // Loan type chips
                              _LoanTypeSelector(
                                  inputState: inputState,
                                  notifier: notifier,
                                  s: s,
                                  onEdit: () {}),
                              const SizedBox(height: AppSpacing.lg),
                              const Divider(height: 1),
                              // Advanced toggle
                              Semantics(
                                  label: _advancedExpanded
                                      ? (isEs
                                          ? 'Ocultar opciones avanzadas'
                                          : 'Hide advanced options')
                                      : (isEs
                                          ? 'Mostrar opciones avanzadas'
                                          : 'Show advanced options'),
                                  button: true,
                                  child: InkWell(
                                    onTap: () => setState(() =>
                                        _advancedExpanded = !_advancedExpanded),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.smPlus),
                                      child: Row(children: [
                                        Icon(
                                          _advancedExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: AppTheme.primary,
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: Text(s.advancedOptions,
                                              style: const TextStyle(
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.w600,
                                              )),
                                        ),
                                        if (_advancedExpanded)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: AppSpacing.sm,
                                                vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary
                                                  .withValues(alpha: 0.10),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadius.mdPlus),
                                            ),
                                            child: Text(
                                              isEs ? 'Ocultar' : 'Hide',
                                              style: const TextStyle(
                                                fontSize: AppTextSize.xs,
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ]),
                                    ),
                                  )), // Semantics + InkWell
                              if (_advancedExpanded) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    color:
                                        CalcwiseTheme.of(context).surfaceHigh,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.lg),
                                  ),
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(children: [
                                    _buildField(s.propertyTaxRate, _taxCtrl,
                                        suffix: '%',
                                        percent: true,
                                        onChanged: (v) =>
                                            notifier.updatePropertyTaxRate(
                                                double.tryParse(v.replaceAll(
                                                        ',', '.')) ??
                                                    1.1)),
                                    const SizedBox(height: AppSpacing.md),
                                    _buildField(s.homeInsurance, _insuranceCtrl,
                                        prefix: '\$',
                                        suffix: '/yr',
                                        onChanged: (v) =>
                                            notifier.updateHomeInsurance(
                                                double.tryParse(v.replaceAll(
                                                        ',', '.')) ??
                                                    1750)),
                                    const SizedBox(height: AppSpacing.md),
                                    _buildField(s.hoaFees, _hoaCtrl,
                                        prefix: '\$',
                                        suffix: '/mo',
                                        onChanged: (v) => notifier.updateHoa(
                                            double.tryParse(
                                                    v.replaceAll(',', '.')) ??
                                                0)),
                                    const SizedBox(height: AppSpacing.md),
                                    _buildField(
                                      isEs
                                          ? 'Ingreso Mensual Bruto (opcional)'
                                          : 'Monthly Gross Income (optional)',
                                      _incomeCtrl,
                                      prefix: '\$',
                                      onChanged: (v) => setState(() {
                                        _monthlyIncome = double.tryParse(
                                                v.replaceAll(',', '')) ??
                                            0.0;
                                      }),
                                      currency: true,
                                    ),
                                  ]),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              // ── AnimatedSwitcher for results ────────────
                              AnimatedSwitcher(
                                duration: AppDuration.base,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.04),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: result != null
                                    ? KeyedSubtree(
                                        key: const ValueKey('results'),
                                        child: CalcwisePageEntrance(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Breakdown card
                                              CalcwiseStaggerItem(
                                                index: 2,
                                                child: _BreakdownCard(
                                                    result: result,
                                                    s: s,
                                                    isEs: isEs),
                                              ),
                                                              // ── Decision Timeline ──────────────────────
                                              const SizedBox(
                                                  height: AppSpacing.md),
                                              CalcwiseStaggerItem(
                                                index: 3,
                                                child: _DecisionTimeline(
                                                  result: result,
                                                  termYears: inputState.termYears,
                                                  isEs: isEs,
                                                ),
                                              ),
                                              // ── Reverse-Solve: max affordable home price ─
                                              const SizedBox(
                                                  height: AppSpacing.md),
                                              CalcwiseStaggerItem(
                                                  index: 4,
                                                  child: ReverseSolveCard(
                                                    title: isEs
                                                        ? '¿Qué precio puedo pagar?'
                                                        : 'What home price can I afford?',
                                                    targetLabel: isEs
                                                        ? 'Pago mensual objetivo'
                                                        : 'Target monthly payment',
                                                    resultLabel: isEs
                                                        ? 'Precio máximo'
                                                        : 'Max home price',
                                                    prefix: '\$',
                                                    minBound: 50000,
                                                    maxBound: 2000000,
                                                    targetValue: 0,
                                                    compute: (homePrice) {
                                                      // Monthly P&I for a candidate home price,
                                                      // reusing the user's current down %, rate, term.
                                                      final downPct = inputState
                                                          .downPaymentPct;
                                                      final loanAmount =
                                                          homePrice *
                                                              (1 -
                                                                  downPct /
                                                                      100);
                                                      final r = inputState
                                                              .annualRatePct /
                                                          100 /
                                                          12;
                                                      final n =
                                                          inputState.termYears *
                                                              12;
                                                      if (r == 0)
                                                        return loanAmount / n;
                                                      final f = pow(1 + r, n);
                                                      return loanAmount *
                                                          r *
                                                          f /
                                                          (f - 1);
                                                    },
                                                  )),
                                              // ── Stress Test Banner ─────────────────────
                                              const SizedBox(
                                                  height: AppSpacing.sm),
                                              CalcwiseStaggerItem(
                                                  index: 5,
                                                  child: Semantics(
                                                      label: isEs
                                                          ? 'Prueba de estrés: si el interés sube a ${result.stressTestRate.toStringAsFixed(2)}%, tu pago mensual sería ${AmountFormatter.ui(result.stressTestMonthly, 'USD')}'
                                                          : 'Stress test: if rate rises to ${result.stressTestRate.toStringAsFixed(2)}%, monthly P&I would be ${AmountFormatter.ui(result.stressTestMonthly, 'USD')}',
                                                      child: Container(
                                                        width: double.infinity,
                                                        padding:
                                                            const EdgeInsets
                                                                .all(AppSpacing
                                                                    .mdPlus),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppTheme
                                                              .accentWarn
                                                              .withValues(
                                                                  alpha: 0.08),
                                                          border: Border.all(
                                                              color: AppTheme
                                                                  .accentWarn
                                                                  .withValues(
                                                                      alpha:
                                                                          0.4)),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      AppRadius
                                                                          .lg),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(children: [
                                                              const Icon(
                                                                  Icons
                                                                      .warning_amber_rounded,
                                                                  color: AppTheme
                                                                      .accentWarn,
                                                                  size: 18),
                                                              const SizedBox(
                                                                  width:
                                                                      AppRadius
                                                                          .sm),
                                                              Text(
                                                                isEs
                                                                    ? 'Prueba de Estrés (+2%)'
                                                                    : 'Stress Test (+2%)',
                                                                style:
                                                                    const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: AppTheme
                                                                      .accentWarn,
                                                                  fontSize:
                                                                      AppTextSize
                                                                          .body,
                                                                ),
                                                              ),
                                                              InfoTooltip(
                                                                title: isEs
                                                                    ? 'Prueba de Estrés'
                                                                    : 'Stress Test',
                                                                body: isEs
                                                                    ? 'Su tasa de calificación es su tasa contractual + 2%. Los prestamistas usan esto para asegurarse de que pueda pagar si suben las tasas.'
                                                                    : 'Your qualifying rate is your contract rate + 2%. Lenders use this to ensure you can still afford payments if interest rates rise.',
                                                              ),
                                                            ]),
                                                            const SizedBox(
                                                                height:
                                                                    AppRadius
                                                                        .sm),
                                                            Text(
                                                              isEs
                                                                  ? 'Si el interés sube a ${result.stressTestRate.toStringAsFixed(2)}%, tu pago mensual sería: ${AmountFormatter.ui(result.stressTestMonthly, 'USD')}'
                                                                  : 'If your rate rises to ${result.stressTestRate.toStringAsFixed(2)}%, your monthly P&I would be: ${AmountFormatter.ui(result.stressTestMonthly, 'USD')}',
                                                              style:
                                                                  const TextStyle(
                                                                color: AppTheme
                                                                    .accentWarn,
                                                                fontSize:
                                                                    AppTextSize
                                                                        .md,
                                                                height: 1.4,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ))), // Semantics (stress test) + CalcwiseStaggerItem
                                              // ── Smart Insights ─────────────────────────
                                              const SizedBox(
                                                  height: AppSpacing.md),
                                              _buildInsightCard(
                                                result: result!,
                                                inputState: inputState,
                                                isEs: isEs,
                                              ),
                                              // ── Affordability badge ─────────────────────
                                              if (_monthlyIncome > 0) ...[
                                                const SizedBox(
                                                    height: AppSpacing.md),
                                                _AffordabilityBadge(
                                                  pitiPayment: result
                                                      .monthly.pitiPayment,
                                                  monthlyIncome: _monthlyIncome,
                                                  isEs: isEs,
                                                ),
                                              ],
                                              const SizedBox(
                                                  height: AppSpacing.md),
                                              SaveScenarioButton(
                                                onSave: _saveScenario,
                                              ),
                                              const SizedBox(
                                                  height: AppSpacing.sm),
                                              // PDF + Share — secondary actions
                                              Row(children: [
                                                Expanded(
                                                  child: ValueListenableBuilder<
                                                      bool>(
                                                    valueListenable:
                                                        freemiumService
                                                            .hasFullAccessNotifier,
                                                    builder: (context,
                                                        isPremium, _) {
                                                      return TextButton.icon(
                                                        onPressed: isPremium
                                                            ? () async {
                                                                try {
                                                                  await PdfExportService
                                                                      .exportMortgage(
                                                                          context,
                                                                          inputState,
                                                                          result,
                                                                          isEs: isEs);
                                                                  AnalyticsService
                                                                      .instance
                                                                      .logPdfExported();
                                                                  if (context
                                                                      .mounted) {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content: Text(isEs
                                                                            ? 'PDF exportado con éxito'
                                                                            : 'PDF exported successfully'),
                                                                        behavior:
                                                                            SnackBarBehavior.floating,
                                                                        duration:
                                                                            const Duration(seconds: 2),
                                                                      ),
                                                                    );
                                                                  }
                                                                } catch (_) {
                                                                  if (context
                                                                      .mounted) {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content: Text(isEs
                                                                            ? 'Error al exportar PDF'
                                                                            : 'Export failed'),
                                                                        behavior:
                                                                            SnackBarBehavior.floating,
                                                                      ),
                                                                    );
                                                                  }
                                                                }
                                                              }
                                                            : () {
                                                                PdfExportService
                                                                    .showUnlockOrPay(
                                                                        context,
                                                                        () async {
                                                                  try {
                                                                    await PdfExportService.exportMortgage(
                                                                        context,
                                                                        inputState,
                                                                        result,
                                                                        isEs: isEs);
                                                                    await AnalyticsService
                                                                        .instance
                                                                        .logPdfExported();
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(isEs
                                                                              ? 'PDF exportado con éxito'
                                                                              : 'PDF exported successfully'),
                                                                          behavior:
                                                                              SnackBarBehavior.floating,
                                                                          duration:
                                                                              const Duration(seconds: 2),
                                                                        ),
                                                                      );
                                                                    }
                                                                  } catch (_) {
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger.of(
                                                                              context)
                                                                          .showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(isEs
                                                                              ? 'Error al exportar PDF'
                                                                              : 'Export failed'),
                                                                          behavior:
                                                                              SnackBarBehavior.floating,
                                                                        ),
                                                                      );
                                                                    }
                                                                  }
                                                                });
                                                              },
                                                        icon: Icon(
                                                            isPremium
                                                                ? Icons
                                                                    .picture_as_pdf_rounded
                                                                : Icons
                                                                    .lock_outline,
                                                            size: 18),
                                                        label: Text(
                                                            isPremium
                                                                ? (s.exportPdf
                                                                    as String)
                                                                : (s.exportPdfPremium
                                                                    as String),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis),
                                                        style: TextButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              const Size(0, 44),
                                                          foregroundColor:
                                                              isPremium
                                                                  ? AppTheme
                                                                      .primary
                                                                  : AppTheme
                                                                      .secondary,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: AppSpacing.sm),
                                                Expanded(
                                                  child: TextButton.icon(
                                                    onPressed: () async {
                                                      final isEs =
                                                          isSpanishNotifier
                                                              .value;
                                                      final text = isEs
                                                          ? '🏠 Resumen hipotecario\n'
                                                              'Precio: ${AmountFormatter.ui(inputState.homePrice, 'USD')}\n'
                                                              'Inicial: ${inputState.downPaymentPct.toStringAsFixed(1)}% (${AmountFormatter.ui(inputState.downPaymentDollar, 'USD')})\n'
                                                              'Tasa: ${inputState.annualRatePct.toStringAsFixed(2)}%\n'
                                                              'Mensual: ${AmountFormatter.ui(result.monthly.pitiPayment, 'USD')}\n'
                                                              'Interés total: ${AmountFormatter.ui(result.totalInterest, 'USD')}\n'
                                                              '— Calculado con Mortgage Calculator US\n\n'
                                                              '📄 Exporta el reporte completo en PDF →'
                                                          : '🏠 Mortgage Summary\n'
                                                              'Price: ${AmountFormatter.ui(inputState.homePrice, 'USD')}\n'
                                                              'Down: ${inputState.downPaymentPct.toStringAsFixed(1)}% (${AmountFormatter.ui(inputState.downPaymentDollar, 'USD')})\n'
                                                              'Rate: ${inputState.annualRatePct.toStringAsFixed(2)}%\n'
                                                              'Monthly: ${AmountFormatter.ui(result.monthly.pitiPayment, 'USD')}\n'
                                                              'Total Interest: ${AmountFormatter.ui(result.totalInterest, 'USD')}\n'
                                                              '— Calculated with Mortgage Calculator US\n\n'
                                                              '📄 Export the full PDF report in the app →';
                                                      try {
                                                        AnalyticsService
                                                            .instance
                                                            .logShareText();
                                                        await Share.share(text);
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                              content: Text(isEs
                                                                  ? 'Compartido con éxito'
                                                                  : 'Shared successfully'),
                                                              behavior:
                                                                  SnackBarBehavior
                                                                      .floating,
                                                              duration:
                                                                  const Duration(
                                                                      seconds:
                                                                          2),
                                                            ),
                                                          );
                                                        }
                                                      } catch (_) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                              content: Text(isEs
                                                                  ? 'Error al compartir'
                                                                  : 'Export failed'),
                                                              behavior:
                                                                  SnackBarBehavior
                                                                      .floating,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    },
                                                    icon: const Icon(
                                                        Icons.share_rounded,
                                                        size: 18),
                                                    label: Text(isEs
                                                        ? 'Compartir'
                                                        : 'Share'),
                                                    style: TextButton.styleFrom(
                                                      minimumSize:
                                                          const Size(0, 44),
                                                    ),
                                                  ),
                                                ),
                                              ]),
                                              const SizedBox(
                                                  height: AppSpacing.md),
                                              Text(
                                                isEs
                                                    ? 'Solo para fines informativos. No es asesoramiento financiero.'
                                                    : 'For informational purposes only. Not financial advice.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: AppTextSize.xs,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ),
                                            ]),
                                        ), // CalcwisePageEntrance closes
                                      )
                                    : Padding(
                                        key: const ValueKey('empty'),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: AppSpacing.xxxl),
                                        child: Column(
                                          children: [
                                            Icon(Icons.home_rounded,
                                                size: 48,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.3)),
                                            const SizedBox(
                                                height: AppSpacing.md),
                                            Text(
                                              isEs
                                                  ? 'Ingresa los valores para ver los resultados'
                                                  : 'Enter values above to see results',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: AppTextSize.body,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              const SizedBox(
                                  height: AppSpacing.listBottomInset),
                            ],
                          ),
                        ), // Form closes
                      ),
                    ),
                  ),
                ],
              ), // CustomScrollView closes
            ), // SafeArea closes
          ), // GestureDetector closes
        );
      },
    );
  }

  /// Recomputes the 15-yr comparison result and caches it.
  /// Call this whenever inputs change (outside build).
  void _recompute15yr(MortgageInputState inputState, MortgageResult result) {
    if (inputState.termYears != 30 || result.loanAmount <= 0) {
      _insightResult15yr = null;
      _insightCacheKey = null;
      return;
    }
    final key = '${inputState.homePrice}_${inputState.downPaymentDollar}_'
        '${inputState.annualRatePct}_${inputState.loanType}_'
        '${inputState.propertyTaxRatePct}_${inputState.homeInsuranceAnnual}_'
        '${inputState.hoaMonthly}';
    if (key == _insightCacheKey) return; // already up to date
    try {
      final pmiRate = (inputState.homePrice > 0 &&
              (inputState.downPaymentDollar / inputState.homePrice) < 0.20 &&
              inputState.loanType != LoanType.va &&
              inputState.loanType != LoanType.usda)
          ? MortgageConstants.pmiDefaultAnnualRate * 100
          : 0.0;
      final now = DateTime.now();
      _insightResult15yr = MortgageCalculator.calculate(MortgageInput(
        homePrice: inputState.homePrice,
        downPayment: inputState.downPaymentDollar,
        annualRatePct: inputState.annualRatePct,
        termYears: 15,
        loanType: inputState.loanType,
        propertyTaxRatePct: inputState.propertyTaxRatePct,
        homeInsuranceAnnual: inputState.homeInsuranceAnnual,
        hoaMonthly: inputState.hoaMonthly,
        pmiAnnualRatePct: pmiRate,
        startDate: DateTime(now.year, now.month + 1),
      ));
      _insightCacheKey = key;
    } catch (_) {
      _insightResult15yr = null;
      _insightCacheKey = null;
    }
  }

  /// Computes insights from the current calculation result and optional income.
  Widget _buildInsightCard({
    required MortgageResult result,
    required MortgageInputState inputState,
    required bool isEs,
  }) {
    // Use the cached 15-yr result (recomputed in build() before this call).
    final double? totalInterest15yr = _insightResult15yr?.totalInterest;

    // Front-end DTI: PITI / income (only when income entered)
    final double? dti =
        _monthlyIncome > 0 ? result.monthly.pitiPayment / _monthlyIncome : null;

    final insights = InsightEngine.generate(
      monthlyPITI: result.monthly.pitiPayment,
      monthlyPI: result.monthly.piPayment,
      totalInterest: result.totalInterest,
      homePrice: inputState.homePrice,
      loanAmount: result.loanAmount,
      annualRatePct: inputState.annualRatePct,
      termYears: inputState.termYears,
      monthlyGrossIncome: _monthlyIncome > 0 ? _monthlyIncome : null,
      totalInterest15yr: totalInterest15yr,
      dti: dti,
      isARM: false,
      isEs: isEs,
    );

    return InsightCard(insights: insights, isSpanish: isEs);
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    String? suffix,
    bool currency = false,
    bool percent = false,
    bool required = false,
    String? errorText,
    String? helperText,
    required Function(String) onChanged,
  }) {
    return Semantics(
      label: label,
      textField: true,
      child: TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: currency
            ? [CurrencyInputFormatter()]
            : percent
                ? [PercentInputFormatter()]
                : [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
          errorText: errorText,
          helperText: helperText,
          helperStyle: const TextStyle(fontSize: AppTextSize.xs),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
        ),
        validator: (v) {
          final es = isSpanishNotifier.value;
          final raw = (v ?? '').trim();
          if (raw.isEmpty) return required ? (es ? 'Requerido' : 'Required') : null;
          final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
          if (cleaned.isEmpty) return es ? 'Inválido' : 'Invalid';
          final n = double.tryParse(cleaned);
          if (n == null) return es ? 'Inválido' : 'Invalid';
          if (n < 0) return es ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
          return null;
        },
        onChanged: onChanged,
      ),
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final MortgageResult? result;
  final AppStrings s;
  const _HeroCard({this.result, required this.s});

  @override
  Widget build(BuildContext context) {
    final pitiPayment = result != null
        ? AmountFormatter.ui(result!.monthly.pitiPayment, 'USD')
        : '--';
    final piPayment = result != null
        ? AmountFormatter.ui(result!.monthly.piPayment, 'USD')
        : null;
    return Semantics(
      label: result != null
          ? 'Total monthly payment PITI: $pitiPayment. '
              'Principal and interest: $piPayment. '
              'Total interest: ${AmountFormatter.ui(result!.totalInterest, 'USD')}. '
              'Total cost: ${AmountFormatter.ui(result!.totalCost, 'USD')}.'
          : 'Monthly payment: enter values above to calculate',
      child: CalcwiseHeroCard(
        label: s.monthlyPITI as String,
        value: pitiPayment,
        rawValue: result?.monthly.pitiPayment,
        valueFormatter: (v) => AmountFormatter.ui(v, 'USD'),
        secondary: result != null
            ? '${s.monthlyPILabel}: $piPayment'
            : null,
        rawStats: result == null
            ? null
            : [
                (
                  label: 'Total Interest',
                  value: result!.totalInterest,
                  formatter: (v) => AmountFormatter.ui(v, 'USD'),
                ),
                (
                  label: 'Total Cost',
                  value: result!.totalCost,
                  formatter: (v) => AmountFormatter.ui(v, 'USD'),
                ),
              ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: Text(label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: AppTextSize.sm,
            )),
      );
}

// ── Term selector ─────────────────────────────────────────────────────────────

class _TermSelector extends ConsumerWidget {
  final MortgageInputState inputState;
  final MortgageInputNotifier notifier;
  final AppStrings s;
  final VoidCallback? onEdit;
  const _TermSelector(
      {required this.inputState, required this.notifier, required this.s, this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.loanTerm, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: MortgageConstants.termPresets.map((term) {
            final selected = inputState.termYears == term;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  label:
                      '$term year loan term, ${selected ? "selected" : "not selected"}',
                  child: ChoiceChip(
                    label: Text('${term}yr'),
                    selected: selected,
                    selectedColor: AppTheme.primary,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppTheme.labelGray,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      onEdit?.call();
                      notifier.updateTerm(term);
                    },
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Loan type selector ────────────────────────────────────────────────────────

class _LoanTypeSelector extends ConsumerWidget {
  final MortgageInputState inputState;
  final MortgageInputNotifier notifier;
  final AppStrings s;
  final VoidCallback? onEdit;
  const _LoanTypeSelector(
      {required this.inputState, required this.notifier, required this.s, this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.loanType, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        _ChipRow<LoanType>(
          values: LoanType.values,
          selected: inputState.loanType,
          label: (t) => t.label,
          onTap: (t) {
            HapticFeedback.selectionClick();
            onEdit?.call();
            notifier.updateLoanType(t);
          },
        ),
      ],
    );
  }
}

// ── Down payment row ──────────────────────────────────────────────────────────

class _DownPaymentRow extends ConsumerWidget {
  final TextEditingController ctrl;
  final MortgageInputState inputState;
  final MortgageInputNotifier notifier;
  final AppStrings s;
  const _DownPaymentRow({
    required this.ctrl,
    required this.inputState,
    required this.notifier,
    required this.s,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(children: [
      Expanded(
        child: TextFormField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: s.downPayment as String,
            suffixText: inputState.downPaymentAsDollar ? null : '%',
            prefixText: inputState.downPaymentAsDollar ? '\$' : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
          ),
          validator: (v) {
            final es = isSpanishNotifier.value;
            final raw = (v ?? '').trim();
            if (raw.isEmpty) return null;
            final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
            if (cleaned.isEmpty) return es ? 'Inválido' : 'Invalid';
            final n = double.tryParse(cleaned);
            if (n == null) return es ? 'Inválido' : 'Invalid';
            if (n < 0) return es ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
            return null;
          },
          onChanged: (v) {
            if (inputState.downPaymentAsDollar) {
              final dollars = double.tryParse(v) ?? 0;
              final pct = inputState.homePrice > 0
                  ? (dollars / inputState.homePrice) * 100
                  : 0.0;
              notifier.updateDownPaymentPct(pct);
            } else {
              notifier.updateDownPaymentPct(double.tryParse(v) ?? 20);
            }
          },
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.labelGray.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _ModeBtn(
            label: '\$',
            selected: inputState.downPaymentAsDollar,
            onTap: () => notifier.toggleDownPaymentMode(true),
          ),
          _ModeBtn(
            label: '%',
            selected: !inputState.downPaymentAsDollar,
            onTap: () => notifier.toggleDownPaymentMode(false),
          ),
        ]),
      ),
    ]);
  }
}

// ── Affordability badge ───────────────────────────────────────────────────────

class _AffordabilityBadge extends StatelessWidget {
  final double pitiPayment;
  final double monthlyIncome;
  final bool isEs;
  const _AffordabilityBadge({
    required this.pitiPayment,
    required this.monthlyIncome,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = pitiPayment / monthlyIncome;
    final pct = (ratio * 100).toStringAsFixed(1);

    final Color badgeColor;
    final String badgeLabel;
    if (ratio < 0.28) {
      badgeColor = AppTheme.accentGood;
      badgeLabel = isEs ? 'Asequible' : 'Affordable';
    } else if (ratio < 0.36) {
      badgeColor = AppTheme.accentWarn;
      badgeLabel = isEs ? 'Al Límite' : 'At the Limit';
    } else {
      badgeColor =
          CalcwiseSemanticColors.error(Theme.of(context).brightness);
      badgeLabel = isEs ? 'Supera el Límite' : 'Over Limit';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_rounded,
              color: badgeColor, size: 20),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: Text(
              isEs
                  ? 'Costo de vivienda: $pct% del ingreso'
                  : 'Housing cost: $pct% of income',
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.w600,
                fontSize: AppTextSize.body,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smPlus, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.sm,
              ),
            ),
          ),
          InfoTooltip(
            title: isEs ? 'Ratio de Costo de Vivienda' : 'Housing Cost Ratio',
            body: isEs
                ? 'Sus costos mensuales de vivienda (capital + interés + impuesto + seguro + HOA + PMI) como % de su ingreso mensual bruto. Los prestamistas generalmente permiten hasta 28-36%.'
                : 'Your monthly housing costs (P&I + property tax + insurance + HOA + PMI) as a % of gross monthly income. Lenders typically allow up to 28–36%.',
          ),
        ],
      ),
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        label: label == '\$' ? 'Dollar amount mode' : 'Percentage mode',
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdPlus, vertical: AppSpacing.mdPlus),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.labelGray,
                  fontWeight: FontWeight.bold,
                )),
          ),
        ),
      );
}

// ── Breakdown card ────────────────────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final MortgageResult? result;
  final AppStrings s;
  final bool isEs;
  const _BreakdownCard(
      {this.result,
      required this.s,
      required this.isEs});

  @override
  Widget build(BuildContext context) {
    final m = result!.monthly;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(children: [
          _Row(s.principal, AmountFormatter.ui(m.principal, 'USD')),
          _Row(s.interest, AmountFormatter.ui(m.interest, 'USD')),
          _Row(s.propertyTax, AmountFormatter.ui(m.propertyTax, 'USD')),
          _Row(s.homeInsurance, AmountFormatter.ui(m.homeInsurance, 'USD')),
          if (m.hoa > 0) _Row(s.hoa, AmountFormatter.ui(m.hoa, 'USD')),
          if (m.pmi > 0)
            _Row(
              result!.isUsda
                  ? s.usdaFeeLabel
                  : '${s.pmiDropsAt} ${result!.pmiDropMonth ?? "?"}${s.mo})',
              AmountFormatter.ui(m.pmi, 'USD'),
              color: result!.isUsda
                  ? AppTheme.accentGood
                  : CalcwiseSemanticColors.warnIcon,
              tooltip: result!.isUsda
                  ? InfoTooltip(
                      title: isEs ? 'Cuota Anual USDA' : 'USDA Annual Fee',
                      body: isEs
                          ? 'Los préstamos USDA incluyen una cuota de garantía inicial del 1% (financiada) y una cuota anual del 0.35%. Nunca se cancela durante la vigencia del préstamo.'
                          : 'USDA loans include a 1% upfront guarantee fee (financed) and 0.35% annual fee. It never drops for the life of the loan.',
                    )
                  : InfoTooltip(
                      title: isEs
                          ? 'PMI — Seguro Hipotecario Privado'
                          : 'PMI — Private Mortgage Insurance',
                      body: isEs
                          ? 'Requerido cuando el pago inicial es menor al 20%. Protege al prestamista, no a usted. Se cancela automáticamente cuando el saldo del préstamo llega al 78% del valor original.'
                          : 'Required when your down payment is less than 20%. Protects the lender, not you. Automatically cancels when your loan balance reaches 78% of the original home value.',
                    ),
            ),
          const Divider(height: 24),
          _Row(s.totalPITI, AmountFormatter.ui(m.pitiPayment, 'USD'), bold: true),
          const SizedBox(height: AppSpacing.sm),
          _Row(s.totalInterest, AmountFormatter.ui(result!.totalInterest, 'USD')),
          _Row(s.totalCost, AmountFormatter.ui(result!.totalCost, 'USD')),
          _Row(s.payoffDate,
              '${result!.payoffDate.month}/${result!.payoffDate.year}'),
          _LtvRow(ltv: result!.currentLtv, isEs: isEs),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  final Widget? tooltip;
  const _Row(this.label, this.value,
      {this.bold = false, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(label,
                          style: TextStyle(color: color ?? AppTheme.labelGray)),
                    ),
                    if (tooltip != null) tooltip!,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(value,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                    color: color ?? (bold ? AppTheme.primary : null),
                  )),
            ],
          ),
        ),
      );
}

// ── LTV gauge row ─────────────────────────────────────────────────────────────

class _LtvRow extends StatelessWidget {
  final double ltv;
  final bool isEs;
  const _LtvRow({required this.ltv, required this.isEs});

  @override
  Widget build(BuildContext context) {
    final pct = ltv.clamp(0.0, 150.0);
    final gaugeValue = (pct / 100.0).clamp(0.0, 1.0);
    final gaugeColor = pct <= 80.0
        ? const Color(0xFF16A34A)
        : pct <= 95.0
            ? AppTheme.accentWarn
            : CalcwiseSemanticColors.error(Theme.of(context).brightness);

    return Semantics(
      label: 'LTV: ${pct.toStringAsFixed(1)}%',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            CalcwiseGauge(
              value: gaugeValue,
              color: gaugeColor,
              size: 40.0,
              strokeWidth: 4.5,
              child: CalcwiseCountUp(
                value: pct,
                formatter: (v) => '${v.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: gaugeColor,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.smPlus),
            Text('LTV', style: TextStyle(color: AppTheme.labelGray)),
            InfoTooltip(
              title: isEs ? 'LTV — Préstamo a Valor' : 'LTV — Loan-to-Value',
              body: isEs
                  ? 'El monto del préstamo dividido por el precio de la casa. Por debajo del 80% LTV = no se requiere PMI. Un LTV más bajo generalmente significa mejores tasas.'
                  : 'Your loan amount divided by the home price. Below 80% LTV = no PMI required. Lower LTV typically means better interest rates.',
            ),
            const Spacer(),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Decision Timeline ─────────────────────────────────────────────────────────

class _DecisionTimeline extends StatelessWidget {
  final MortgageResult result;
  final int termYears;
  final bool isEs;

  const _DecisionTimeline({
    required this.result,
    required this.termYears,
    required this.isEs,
  });

  DateTime _milestoneDate(int monthOffset) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month + 1);
    final m = start.month + monthOffset - 1;
    final y = start.year + m ~/ 12;
    final mo = m % 12 + 1;
    return DateTime(y, mo);
  }

  String _fmt(DateTime d) {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${monthNames[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final totalMonths = termYears * 12;
    final halfwayMonth = (totalMonths / 2).round();
    final showPmi = !result.isUsda && result.pmiDropMonth != null;

    final milestones = <({
      IconData icon,
      Color color,
      String label,
      String sublabel,
    })>[];

    if (showPmi) {
      final d = _milestoneDate(result.pmiDropMonth!);
      milestones.add((
        icon: Icons.shield_outlined,
        color: AppTheme.accentWarn,
        label: isEs ? 'PMI Eliminado' : 'PMI Removed',
        sublabel: isEs
            ? 'Mes ${result.pmiDropMonth} — ${_fmt(d)}'
            : 'Month ${result.pmiDropMonth} — ${_fmt(d)}',
      ));
    }

    final halfDate = _milestoneDate(halfwayMonth);
    milestones.add((
      icon: Icons.trending_up_rounded,
      color: AppTheme.infoIcon,
      label: isEs ? 'Mitad del Camino' : 'Halfway',
      sublabel: isEs
          ? 'Mes $halfwayMonth — ${halfDate.year}'
          : 'Month $halfwayMonth — ${halfDate.year}',
    ));

    final payoffDate = _milestoneDate(totalMonths);
    milestones.add((
      icon: Icons.home_rounded,
      color: AppTheme.accentGood,
      label: isEs ? 'Pagado' : 'Paid Off',
      sublabel: isEs
          ? 'Mes $totalMonths — ${payoffDate.year}'
          : 'Month $totalMonths — ${payoffDate.year}',
    ));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEs ? 'Hitos del Préstamo' : 'Mortgage Timeline',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.body,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(milestones.length * 2 - 1, (i) {
                if (i.isOdd) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: Divider(
                        height: 1,
                        thickness: 1.5,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  );
                }
                final m = milestones[i ~/ 2];
                return Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: m.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: m.color.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(m.icon, color: m.color, size: 22),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        m.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSize.sm,
                          color: m.color,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        m.sublabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppTextSize.xs,
                          color: AppTheme.labelGray,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Generic pill chip row (same style as MortgageUK) ─────────────────────────

class _ChipRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final void Function(T) onTap;

  const _ChipRow({
    required this.values,
    required this.selected,
    required this.label,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs + 2,
      children: values.map((v) {
        final isSelected = v == selected;
        return Semantics(
          label: label(v),
          selected: isSelected,
          button: true,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(v);
            },
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AnimatedContainer(
              duration: AppDuration.fast,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.smPlus),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : CalcwiseTheme.of(context).cardBorder,
                ),
              ),
              child: Text(
                label(v),
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : CalcwiseTheme.of(context).textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}


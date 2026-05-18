import 'dart:async';
import 'dart:math' show pow;
import 'package:calcwise_core/calcwise_core.dart'
    show
        PaywallTrigger,
        CalcwiseTheme,
        CalcwiseStaggerItem,
        CalcwisePageEntrance,
        CalcwiseAdFooter,
        RateWatchService,
        CalcwiseReviewService,
        ReverseSolveCard,
        CalcwiseHeroCard;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/services/pdf_export_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/models/mortgage_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../providers/mortgage_providers.dart';
import '../history/history_screen.dart' show paywallSession, HistoryScreen;
import '../../../main.dart' show adService, paywallSession, isSpanishNotifier, preFillNotifier;
import '../../../core/services/analytics_service.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/info_tooltip.dart';
import '../../../core/utils/insight_engine.dart';
import '../../widgets/insight_card.dart';

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
  final _incomeCtrl = TextEditingController();
  double _monthlyIncome = 0.0;
  bool _advancedExpanded = false;
  String? _homePriceError;

  // Cached 15-yr comparison result — recomputed only when inputs change.
  MortgageResult? _insightResult15yr;
  String? _insightCacheKey;

  final _fmt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
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

  Future<void> _saveToHistory({bool showFeedback = false}) async {
    final result = ref.read(mortgageResultProvider);
    if (result == null || result.loanAmount <= 0) return;

    final inputState = ref.read(mortgageInputProvider);
    final label =
        '${inputState.homePrice ~/ 1000}K · ${inputState.annualRatePct.toStringAsFixed(2)}% · ${inputState.termYears}yr';
    try {
      await DatabaseHelper.instance.insertHistory({
        'home_price': inputState.homePrice,
        'down_percent': inputState.downPaymentPct,
        'annual_rate': inputState.annualRatePct,
        'monthly_payment': result.monthly.pitiPayment,
        'total_interest': result.totalInterest,
        'loan_amount': result.loanAmount,
        'loan_type': inputState.loanType.label,
        'term_years': inputState.termYears,
        'tax_rate': inputState.propertyTaxRatePct,
        'insurance': inputState.homeInsuranceAnnual,
        'hoa': inputState.hoaMonthly,
        'created_at': DateTime.now().toIso8601String(),
        'label': label,
      });
    } catch (_) {}
    try {
      AnalyticsService.instance.logSave();
    } catch (_) {}

    // Emotional trigger: accessible monthly payment → ask for review
    if (result.monthly.pitiPayment < 3000 && result.monthly.pitiPayment > 0) {
      CalcwiseReviewService.instance.requestAfterPremium();
    }

    // Refresh history tab immediately
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
    unawaited(RateWatchService.instance
        .checkRate(inputState.annualRatePct, appLabel: 'MortgageUS'));
    AnalyticsService.instance.logHistorySaved();
    if (mounted) {
      final trigger = await paywallSession.recordAction();
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }

    if (!mounted) return;
    final isEs = isSpanishNotifier.value;

    // Free users: FIFO cap — remove oldest, show paywallSession, informative snackbar
    if (!freemiumService.hasFullAccess) {
      final count = await DatabaseHelper.instance.countHistory();
      if (count > freemiumService.historyLimit) {
        await DatabaseHelper.instance.deleteOldestHistory();
        HistoryScreen.refreshNotifier.value++;
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isEs
                ? 'Guardado · entrada más antigua reemplazada · ${freemiumService.historyLimit}/${freemiumService.historyLimit} slots'
                : 'Saved · oldest entry replaced · ${freemiumService.historyLimit}/${freemiumService.historyLimit} free slots'),
            action: SnackBarAction(
              label: isEs ? 'Ilimitado' : 'Unlock unlimited',
              onPressed: () => IAPService.instance.buy(),
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
    }

    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isEs ? 'Cálculo guardado' : 'Calculation saved'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(mortgageResultProvider);
    final inputState = ref.watch(mortgageInputProvider);
    final notifier = ref.read(mortgageInputProvider.notifier);

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
              child: CalcwisePageEntrance(
                  child: CustomScrollView(
                slivers: [
                  // ── Hero card ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: CalcwiseStaggerItem(
                      index: 0,
                      child: _HeroCard(result: result, s: s),
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
                                  s: s),
                              const SizedBox(height: AppSpacing.md),
                              // Loan type chips
                              _LoanTypeSelector(
                                  inputState: inputState,
                                  notifier: notifier,
                                  s: s),
                              const SizedBox(height: AppSpacing.lg),
                              const Divider(height: 1),
                              // Advanced toggle
                              InkWell(
                                onTap: () => setState(() =>
                                    _advancedExpanded = !_advancedExpanded),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
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
                                            horizontal: AppSpacing.sm, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary
                                              .withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(
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
                              ),
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
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Breakdown card
                                              _BreakdownCard(
                                                  result: result,
                                                  fmt: _fmt,
                                                  fmtK: _fmtK,
                                                  s: s,
                                                  isEs: isEs),
                                              // ── Reverse-Solve: max affordable home price ─
                                              const SizedBox(height: AppSpacing.md),
                                              ReverseSolveCard(
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
                                                  final downPct =
                                                      inputState.downPaymentPct;
                                                  final loanAmount = homePrice *
                                                      (1 - downPct / 100);
                                                  final r =
                                                      inputState.annualRatePct /
                                                          100 /
                                                          12;
                                                  final n =
                                                      inputState.termYears * 12;
                                                  if (r == 0)
                                                    return loanAmount / n;
                                                  final f = pow(1 + r, n);
                                                  return loanAmount *
                                                      r *
                                                      f /
                                                      (f - 1);
                                                },
                                              ),
                                              // ── Stress Test Banner ─────────────────────
                                              const SizedBox(height: AppSpacing.sm),
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(
                                                    AppSpacing.mdPlus),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.accentWarn
                                                      .withValues(alpha: 0.08),
                                                  border: Border.all(
                                                      color: AppTheme.accentWarn
                                                          .withValues(
                                                              alpha: 0.4)),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          AppRadius.lg),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      const Icon(
                                                          Icons
                                                              .warning_amber_rounded,
                                                          color: AppTheme
                                                              .accentWarn,
                                                          size: 18),
                                                      const SizedBox(width: AppRadius.sm),
                                                      Text(
                                                        isEs
                                                            ? 'Prueba de Estrés (+2%)'
                                                            : 'Stress Test (+2%)',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: AppTheme
                                                              .accentWarn,
                                                          fontSize:
                                                              AppTextSize.body,
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
                                                    const SizedBox(height: AppRadius.sm),
                                                    Text(
                                                      isEs
                                                          ? 'Si el interés sube a ${result.stressTestRate.toStringAsFixed(2)}%, tu pago mensual sería: ${_fmt.format(result.stressTestMonthly)}'
                                                          : 'If your rate rises to ${result.stressTestRate.toStringAsFixed(2)}%, your monthly P&I would be: ${_fmt.format(result.stressTestMonthly)}',
                                                      style: const TextStyle(
                                                        color:
                                                            AppTheme.accentWarn,
                                                        fontSize:
                                                            AppTextSize.md,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // ── Smart Insights ─────────────────────────
                                              const SizedBox(height: AppSpacing.md),
                                              _buildInsightCard(
                                                result: result!,
                                                inputState: inputState,
                                                isEs: isEs,
                                              ),
                                              // ── Affordability badge ─────────────────────
                                              if (_monthlyIncome > 0) ...[
                                                const SizedBox(height: AppSpacing.md),
                                                _AffordabilityBadge(
                                                  pitiPayment: result
                                                      .monthly.pitiPayment,
                                                  monthlyIncome: _monthlyIncome,
                                                  isEs: isEs,
                                                ),
                                              ],
                                              const SizedBox(height: AppSpacing.md),
                                              // Save button — primary CTA
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  HapticFeedback.mediumImpact();
                                                  _saveToHistory(
                                                      showFeedback: true);
                                                },
                                                icon: const Icon(
                                                    Icons.bookmark_add_rounded),
                                                label: Text(s.saveCalc),
                                                style: ElevatedButton.styleFrom(
                                                  minimumSize: const Size(
                                                      double.infinity, 52),
                                                ),
                                              ),
                                              const SizedBox(height: AppSpacing.sm),
                                              // PDF + Share — secondary actions
                                              Row(children: [
                                                Expanded(
                                                  child: ValueListenableBuilder<
                                                      bool>(
                                                    valueListenable:
                                                        freemiumService
                                                            .isPremiumNotifier,
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
                                                                          result);
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
                                                                        result);
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
                                                const SizedBox(width: AppSpacing.sm),
                                                Expanded(
                                                  child: TextButton.icon(
                                                    onPressed: () async {
                                                      final isEs =
                                                          isSpanishNotifier
                                                              .value;
                                                      if (!freemiumService
                                                          .hasFullAccess) {
                                                        final trigger =
                                                            await paywallSession
                                                                .recordAction();
                                                        if (trigger ==
                                                            PaywallTrigger
                                                                .soft) {
                                                          PaywallSoft.show(
                                                              context);
                                                          return;
                                                        }
                                                        if (trigger ==
                                                            PaywallTrigger
                                                                .hard) {
                                                          PaywallHard.show(
                                                              context);
                                                          return;
                                                        }
                                                      }
                                                      final fmt =
                                                          NumberFormat.currency(
                                                              locale: 'en_US',
                                                              symbol: r'$',
                                                              decimalDigits: 0);
                                                      final text = isEs
                                                          ? '🏠 Resumen hipotecario\n'
                                                              'Precio: ${fmt.format(inputState.homePrice)}\n'
                                                              'Inicial: ${inputState.downPaymentPct.toStringAsFixed(1)}% (${fmt.format(inputState.downPaymentDollar)})\n'
                                                              'Tasa: ${inputState.annualRatePct.toStringAsFixed(2)}%\n'
                                                              'Mensual: ${fmt.format(result.monthly.pitiPayment)}\n'
                                                              'Interés total: ${fmt.format(result.totalInterest)}\n'
                                                              '— Calculado con Mortgage Calculator US'
                                                          : '🏠 Mortgage Summary\n'
                                                              'Price: ${fmt.format(inputState.homePrice)}\n'
                                                              'Down: ${inputState.downPaymentPct.toStringAsFixed(1)}% (${fmt.format(inputState.downPaymentDollar)})\n'
                                                              'Rate: ${inputState.annualRatePct.toStringAsFixed(2)}%\n'
                                                              'Monthly: ${fmt.format(result.monthly.pitiPayment)}\n'
                                                              'Total Interest: ${fmt.format(result.totalInterest)}\n'
                                                              '— Calculated with Mortgage Calculator US';
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
                                              const SizedBox(height: AppSpacing.md),
                                              Text(
                                                isEs
                                                    ? 'Solo para fines informativos. No es asesoramiento financiero.'
                                                    : 'For informational purposes only. Not financial advice.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ),
                                            ]),
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
                                            const SizedBox(height: AppSpacing.md),
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
                              const SizedBox(height: 80),
                            ],
                          ),
                        ), // Form closes
                      ),
                    ),
                  ),
                ],
              )), // CalcwisePageEntrance closes
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
    bool required = false,
    String? errorText,
    String? helperText,
    required Function(String) onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: currency
          ? [CurrencyInputFormatter()]
          : [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        errorText: errorText,
        helperText: helperText,
        helperStyle: const TextStyle(fontSize: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
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
      onChanged: onChanged,
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
    final fmt =
        NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
    return CalcwiseHeroCard(
      label: s.monthlyPI as String,
      value: result != null ? fmt.format(result!.monthly.piPayment) : '--',
      secondary: result != null
          ? '${s.totalPITI}: ${fmt.format(result!.monthly.pitiPayment)}'
          : null,
      stats: result == null
          ? null
          : [
              (
                label: 'Total Interest',
                value: fmt.format(result!.totalInterest),
              ),
              (
                label: 'Total Cost',
                value: fmt.format(result!.totalCost),
              ),
            ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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
  const _TermSelector(
      {required this.inputState, required this.notifier, required this.s});

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
  const _LoanTypeSelector(
      {required this.inputState, required this.notifier, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.loanType, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          children: LoanType.values.map((type) {
            final selected = inputState.loanType == type;
            return Semantics(
              label:
                  '${type.label} loan type, ${selected ? "selected" : "not selected"}',
              child: ChoiceChip(
                label: Text(type.label),
                selected: selected,
                selectedColor: AppTheme.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.labelGray,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  notifier.updateLoanType(type);
                },
              ),
            );
          }).toList(),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
          ),
          validator: (v) {
            final raw = (v ?? '').trim();
            if (raw.isEmpty) return null;
            final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
            if (cleaned.isEmpty) return 'Invalid';
            final n = double.tryParse(cleaned);
            if (n == null) return 'Invalid';
            if (n < 0) return 'Must be ≥ 0';
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
      badgeColor = CalcwiseSemanticColors.errorDark;
      badgeLabel = isEs ? 'Supera el Límite' : 'Over Limit';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smPlus, vertical: AppSpacing.xs),
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdPlus, vertical: AppSpacing.mdPlus),
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
      );
}

// ── Breakdown card ────────────────────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final MortgageResult? result;
  final NumberFormat fmt;
  final NumberFormat fmtK;
  final AppStrings s;
  final bool isEs;
  const _BreakdownCard(
      {this.result,
      required this.fmt,
      required this.fmtK,
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
          _Row(s.principal, fmt.format(m.principal)),
          _Row(s.interest, fmt.format(m.interest)),
          _Row(s.propertyTax, fmt.format(m.propertyTax)),
          _Row(s.homeInsurance, fmt.format(m.homeInsurance)),
          if (m.hoa > 0) _Row(s.hoa, fmt.format(m.hoa)),
          if (m.pmi > 0)
            _Row(
              result!.isUsda
                  ? s.usdaFeeLabel
                  : '${s.pmiDropsAt} ${result!.pmiDropMonth ?? "?"}${s.mo})',
              fmt.format(m.pmi),
              color: result!.isUsda ? AppTheme.accentGood : CalcwiseSemanticColors.warnIcon,
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
          _Row(s.totalPITI, fmt.format(m.pitiPayment), bold: true),
          const SizedBox(height: AppSpacing.sm),
          _Row(s.totalInterest, fmtK.format(result!.totalInterest)),
          _Row(s.totalCost, fmtK.format(result!.totalCost)),
          _Row(s.payoffDate,
              '${result!.payoffDate.month}/${result!.payoffDate.year}'),
          _Row(
            isEs ? 'LTV' : 'LTV',
            '${result!.currentLtv.toStringAsFixed(1)}%',
            tooltip: InfoTooltip(
              title: isEs ? 'LTV — Préstamo a Valor' : 'LTV — Loan-to-Value',
              body: isEs
                  ? 'El monto del préstamo dividido por el precio de la casa. Por debajo del 80% LTV = no se requiere PMI. Un LTV más bajo generalmente significa mejores tasas.'
                  : 'Your loan amount divided by the home price. Below 80% LTV = no PMI required. Lower LTV typically means better interest rates.',
            ),
          ),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(color: color ?? AppTheme.labelGray)),
                if (tooltip != null) tooltip!,
              ],
            ),
            Text(value,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                  color: color ?? (bold ? AppTheme.primary : null),
                )),
          ],
        ),
      );
}

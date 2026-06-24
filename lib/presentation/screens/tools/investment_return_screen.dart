import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/irr_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show adService, paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../widgets/save_scenario_button.dart';
import '../history/history_screen.dart' show HistoryScreen;

// ── Color for Investment Return tool icon (emerald-teal) ──────────────────────
const Color _kToolColor = Color(0xFF0D9488); // teal-600

class InvestmentReturnScreen extends ConsumerStatefulWidget {
  const InvestmentReturnScreen({super.key});

  @override
  ConsumerState<InvestmentReturnScreen> createState() =>
      _InvestmentReturnScreenState();
}

class _InvestmentReturnScreenState
    extends ConsumerState<InvestmentReturnScreen> {
  // ── Controllers ──────────────────────────────────────────────────────────
  late final TextEditingController _priceCtrl;
  final _rentCtrl = TextEditingController(text: '2500');
  final _discountCtrl = TextEditingController(text: '10');

  // ── State ─────────────────────────────────────────────────────────────────
  late double _downPct;
  double _appreciation = 3.0;
  int _holdYears = 10;
  bool _analyticsLogged = false;

  static const List<int> _holdOptions = [5, 10, 15, 20];

  double _roundTo(double v, double step) => (v / step).round() * step;

  // ── Interest rate used for mortgage calculation ───────────────────────────
  late double _defaultRate;
  static const int _defaultTerm = 30;
  static const double _expenseRatio = 0.30; // 30% of gross rent

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('investment_return');
    AnalyticsService.instance.maybeLogFirstCalculate();
    // Pre-fill from current calculator values
    final input = ref.read(mortgageInputProvider);
    final price = input.homePrice > 0 ? input.homePrice : 400000;
    _downPct = input.downPaymentPct.clamp(5.0, 50.0);
    _defaultRate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
    _priceCtrl = TextEditingController(
        text: NumberFormat('#,##0').format(price.round()));
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'investment_return');
    _priceCtrl.dispose();
    _rentCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    // Schedule auto-save
    final result = _calculate();
    if (result != null) {
      final price = result.price;
      final hash = ResultHasher.hashMixed({
        'home_price': _roundTo(price, 5000),
        'down_pct': _roundTo(_downPct, 5.0),
        'appreciation': _roundTo(_appreciation, 1.0),
        'hold_years': _holdYears.toDouble(),
      });
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'investment_return',
        inputHash: hash,
        l1: {
          'home_price': price,
          'down_pct': _downPct,
          'appreciation_rate': _appreciation,
          'hold_years': _holdYears,
          'total_return_pct': result.cashOnCash,
        },
        l2: {
          'inputs': {
            'home_price': price,
            'down_pct': _downPct,
            'appreciation_rate': _appreciation,
            'hold_years': _holdYears,
          },
          'results': {
            'future_value': price * pow(1 + _appreciation / 100.0, _holdYears.toDouble()),
            'equity': result.downAmt,
            'total_return': result.equityMult,
            'annualized_return': result.irr,
            'coc': result.cashOnCash,
          },
        },
      );
      HistoryScreen.refreshNotifier.value++;
      adService.onSave();
    }
    adService.onAction();
    if (!_analyticsLogged) {
      _analyticsLogged = true;
      AnalyticsService.instance.logInvestmentReturnCalculated();
      final trigger = await paywallSession.recordAction();
      if (mounted) {
        if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
        if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
      }
    }
  }

  Future<void> _saveScenario(String? label) async {
    HapticFeedback.mediumImpact();
    final result = _calculate();
    if (result == null) return;
    final price = result.price;
    final hash = ResultHasher.hashMixed({
      'home_price': _roundTo(price, 5000),
      'down_pct': _roundTo(_downPct, 5.0),
      'appreciation': _roundTo(_appreciation, 1.0),
      'hold_years': _holdYears.toDouble(),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'investment_return',
      inputHash: hash,
      l1: {
        'home_price': price,
        'down_pct': _downPct,
        'appreciation_rate': _appreciation,
        'hold_years': _holdYears,
        'total_return_pct': result.cashOnCash,
      },
      l2: {
        'inputs': {
          'home_price': price,
          'down_pct': _downPct,
          'appreciation_rate': _appreciation,
          'hold_years': _holdYears,
        },
        'results': {
          'future_value': price * pow(1 + _appreciation / 100.0, _holdYears.toDouble()),
          'equity': result.downAmt,
          'total_return': result.equityMult,
          'annualized_return': result.irr,
          'coc': result.cashOnCash,
        },
      },
      label: label,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  Future<void> _exportPdf(bool isEs) async {
    final result = _calculate();
    if (result == null) return;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportInvestmentReturn(
        context,
        price: result.price,
        downPct: _downPct,
        rent: _parseAmount(_rentCtrl.text),
        appreciation: _appreciation,
        holdYears: _holdYears,
        rate: _defaultRate,
        downAmt: result.downAmt,
        initialInv: result.initialInv,
        loanAmt: result.loanAmt,
        mortgageMo: result.mortgageMo,
        monthlyCF: result.monthlyCF,
        cashOnCash: result.cashOnCash,
        irr: result.irr,
        npv: result.npv,
        equityMult: result.equityMult,
        isEs: isEs,
      );
      AnalyticsService.instance.logPdfExported();
    });
  }

  // ── Core calculation ──────────────────────────────────────────────────────
  _InvestmentResult? _calculate() {
    final price = _parseAmount(_priceCtrl.text);
    final rent = _parseAmount(_rentCtrl.text);
    final discount = double.tryParse(_discountCtrl.text) ?? 10.0;

    if (price <= 0 || rent <= 0) return null;

    final downAmt = price * _downPct / 100;
    final loanAmt = price - downAmt;
    final closingCosts = price * 0.02; // 2% closing costs estimate
    final initialInv = downAmt + closingCosts;

    final mortgageMo = loanAmt > 0
        ? MortgageCalculator.calcMonthlyPayment(
            loanAmount: loanAmt,
            annualRatePct: _defaultRate,
            termYears: _defaultTerm,
          )
        : 0.0;

    final expensesMo = rent * _expenseRatio;
    final monthlyCF = rent - mortgageMo - expensesMo;
    final annualCF = monthlyCF * 12;
    final annualMortgage = mortgageMo * 12;
    final cashOnCash = initialInv > 0 ? annualCF / initialInv * 100 : 0.0;

    final flows = IrrEngine.buildRentalCashFlows(
      initialInvestment: initialInv,
      annualCashFlow: annualCF,
      propertyValue: price,
      appreciationPercent: _appreciation,
      annualMortgagePayment: annualMortgage,
      loanAmount: loanAmt,
      annualRatePct: _defaultRate,
      termMonths: _defaultTerm * 12,
      years: _holdYears,
    );

    final irrVal = IrrEngine.irr(flows);
    final npvVal = IrrEngine.npv(discount, flows);

    // Equity multiple = total cash in / initial investment
    final totalCashIn = flows.skip(1).fold(0.0, (a, b) => a + b);
    final equityMult =
        initialInv > 0 ? (totalCashIn + initialInv) / initialInv : 0.0;

    return _InvestmentResult(
      price: price,
      downAmt: downAmt,
      initialInv: initialInv,
      loanAmt: loanAmt,
      mortgageMo: mortgageMo,
      monthlyCF: monthlyCF,
      cashOnCash: cashOnCash,
      irr: irrVal,
      npv: npvVal,
      equityMult: equityMult,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final result = _calculate();

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Retorno de Inversión' : 'Investment Return'),
          ),
          body: CalcwisePageEntrance(
              child: Column(children: [
            Expanded(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Purchase price ─────────────────────────────────────────
                  _SectionLabel(
                      label: isEs ? 'Precio de compra' : 'Purchase Price'),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: _inputDecor(
                      label: isEs ? 'Precio de compra' : 'Purchase Price',
                      prefix: '\$',
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _onInteraction();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Down payment slider ────────────────────────────────────
                  _SliderRow(
                    labelEn: 'Down Payment',
                    labelEs: 'Enganche',
                    value: _downPct,
                    valueSuffix: '%',
                    displayValue:
                        result != null ? AmountFormatter.ui(result.downAmt, 'USD') : '—',
                    min: 3.0,
                    max: 50.0,
                    divisions: 470,
                    minLabel: '3%',
                    maxLabel: '50%',
                    isEs: isEs,
                    onChanged: (v) => setState(() => _downPct = v),
                    onChangeEnd: (_) => _onInteraction(),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Monthly rent ──────────────────────────────────────────
                  _SectionLabel(
                      label: isEs
                          ? 'Renta mensual estimada'
                          : 'Monthly Rent Estimate'),
                  TextFormField(
                    controller: _rentCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: _inputDecor(
                      label: isEs ? 'Renta mensual' : 'Monthly Rent',
                      prefix: '\$',
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _onInteraction();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Appreciation slider ────────────────────────────────────
                  _SliderRow(
                    labelEn: 'Annual Appreciation',
                    labelEs: 'Apreciación Anual',
                    value: _appreciation,
                    valueSuffix: '%',
                    displayValue: '${_appreciation.toStringAsFixed(1)}%',
                    min: 0.0,
                    max: 10.0,
                    divisions: 100,
                    minLabel: '0%',
                    maxLabel: '10%',
                    isEs: isEs,
                    onChanged: (v) => setState(() => _appreciation = v),
                    onChangeEnd: (_) => _onInteraction(),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Hold period toggle ─────────────────────────────────────
                  _SectionLabel(
                      label: isEs ? 'Período de tenencia' : 'Hold Period'),
                  const SizedBox(height: AppSpacing.sm),
                  _HoldPeriodToggle(
                    selected: _holdYears,
                    options: _holdOptions,
                    isEs: isEs,
                    onSelect: (v) {
                      setState(() => _holdYears = v);
                      _onInteraction();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Discount rate ─────────────────────────────────────────
                  TextFormField(
                    controller: _discountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecor(
                      label: isEs
                          ? 'Tasa de descuento NPV (%)'
                          : 'NPV Discount Rate (%)',
                      prefix: null,
                      suffix: '%',
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _onInteraction();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Assumptions note ───────────────────────────────────────
                  _AssumptionsBox(isEs: isEs, rate: _defaultRate),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Results (premium-gated) ───────────────────────────────
                  if (result == null)
                    Center(
                      child: Text(
                        isEs
                            ? 'Ingresa un precio y renta válidos'
                            : 'Enter a valid price and rent',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65)),
                      ),
                    )
                  else ...[
                    _ResultsSection(result: result, isEs: isEs),
                    const SizedBox(height: AppSpacing.md),
                    SaveScenarioButton(onSave: _saveScenario, labelEn: 'Save Investment', labelEs: 'Guardar inversión'),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _exportPdf(isEs);
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: Text(isEs ? 'Exportar PDF' : 'Export PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.mdPlus),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.xl)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )),
            const CalcwiseAdFooter(),
          ])),
        );
      },
    );
  }

  InputDecoration _inputDecor({
    required String label,
    String? prefix,
    String? suffix,
  }) =>
      InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
      );

  double _parseAmount(String text) =>
      double.tryParse(text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0.0;
}

// ── Results section (premium gate) ────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final _InvestmentResult result;
  final bool isEs;

  const _ResultsSection({required this.result, required this.isEs});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.hasFullAccessNotifier,
      builder: (context, isPremium, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isRewardedNotifier,
          builder: (context, isRewarded, _) {
            final unlocked = isPremium || isRewarded;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResultsCard(result: result, isEs: isEs, unlocked: unlocked),
                if (!unlocked) ...[
                  const SizedBox(height: AppSpacing.lg),
                  CalcwisePremiumGate(
                    title: isEs
                        ? 'IRR, NPV y análisis completo'
                        : 'IRR, NPV & full analysis',
                    description: isEs
                        ? 'Desbloquea IRR, NPV y análisis completo'
                        : 'Unlock IRR, NPV & full analysis',
                    price: IAPService.instance.localizedPrice,
                    onUnlock: () => PaywallHard.show(context),
                    buttonLabel: isEs ? 'Desbloquear Premium' : 'Unlock Premium',
                    subtitle: isEs
                        ? 'Acceso único · Sin suscripción'
                        : 'One-time purchase · No subscription',
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ── Results card ──────────────────────────────────────────────────────────────

class _ResultsCard extends StatelessWidget {
  final _InvestmentResult result;
  final bool isEs;
  final bool unlocked;

  const _ResultsCard({
    required this.result,
    required this.isEs,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    // When locked, show a placeholder result so real values are never rendered.
    final displayResult = unlocked
        ? result
        : const _InvestmentResult(
            price: 0,
            downAmt: 0,
            initialInv: 0,
            loanAmt: 0,
            mortgageMo: 0,
            monthlyCF: 0,
            cashOnCash: 0,
            irr: 0,
            npv: 0,
            equityMult: 0,
          );

    final verdict = _verdict(displayResult.irr);
    final verdictColor =
        _verdictColor(verdict, Theme.of(context).brightness);
    final verdictLabel = _verdictLabel(verdict, isEs);

    return Column(
      children: [
        Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Verdict badge ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdPlus, vertical: AppSpacing.smPlus),
                decoration: BoxDecoration(
                  color: verdictColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                  border:
                      Border.all(color: verdictColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(_verdictIcon(verdict), color: verdictColor, size: 22),
                    const SizedBox(width: AppSpacing.smPlus),
                    Expanded(
                      child: Text(
                        verdictLabel,
                        style: TextStyle(
                          color: verdictColor,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.bodyMd,
                        ),
                      ),
                    ),
                    Text(
                      unlocked
                          ? '${displayResult.irr.toStringAsFixed(1)}% IRR'
                          : '—',
                      style: TextStyle(
                        color: verdictColor,
                        fontWeight: FontWeight.w600,
                        fontSize: AppTextSize.body,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Cash flow row (always visible — basic metrics) ─────────
              _Row(
                label: isEs ? 'Flujo de caja mensual' : 'Monthly Cash Flow',
                value: '${result.monthlyCF >= 0 ? '+' : ''}'
                    '${AmountFormatter.ui(result.monthlyCF, 'USD')}',
                color: result.monthlyCF >= 0
                    ? AppTheme.accentGood
                    : CalcwiseSemanticColors.error(
                        Theme.of(context).brightness),
                bold: true,
              ),
              _Row(
                label: isEs
                    ? 'Inversión inicial (enganche + cierre)'
                    : 'Initial Investment (down + closing)',
                value: AmountFormatter.ui(result.initialInv, 'USD'),
              ),
              _Row(
                label: isEs
                    ? 'Pago hipotecario mensual'
                    : 'Monthly Mortgage Payment',
                value: AmountFormatter.ui(result.mortgageMo, 'USD'),
              ),
              const Divider(height: 24),

              // ── IRR / NPV ──────────────────────────────────────────────
              _Row(
                label: isEs
                    ? 'TIR (tasa interna de retorno)'
                    : 'IRR (Internal Rate of Return)',
                value: unlocked
                    ? '${displayResult.irr.toStringAsFixed(1)}%'
                    : '—',
                color: unlocked ? verdictColor : null,
                bold: true,
              ),
              _Row(
                label: isEs
                    ? 'VPN (valor presente neto)'
                    : 'NPV (Net Present Value)',
                value: unlocked
                    ? '${displayResult.npv >= 0 ? '+' : ''}'
                        '${AmountFormatter.ui(displayResult.npv, 'USD')}'
                    : '—',
                color: unlocked
                    ? (displayResult.npv >= 0
                        ? AppTheme.accentGood
                        : CalcwiseSemanticColors.error(
                            Theme.of(context).brightness))
                    : null,
                bold: true,
              ),
              const Divider(height: 24),

              // ── ROI metrics ────────────────────────────────────────────
              _Row(
                label: isEs
                    ? 'ROI efectivo anual (cash-on-cash)'
                    : 'Cash-on-Cash ROI',
                value: unlocked
                    ? '${displayResult.cashOnCash.toStringAsFixed(1)}%'
                    : '—',
                color: unlocked
                    ? (displayResult.cashOnCash >= 6
                        ? AppTheme.accentGood
                        : AppTheme.accentWarn)
                    : null,
              ),
              _Row(
                label: isEs ? 'Múltiplo de capital' : 'Equity Multiple',
                value: unlocked
                    ? '${displayResult.equityMult.toStringAsFixed(2)}x'
                    : '—',
              ),

              const SizedBox(height: AppSpacing.sm),
              // ── Legend ─────────────────────────────────────────────────
              _VerdictLegend(isEs: isEs),
            ],
          ),
        ),
      ),
      ],
    );
  }
}

// ── Assumptions box ───────────────────────────────────────────────────────────

class _AssumptionsBox extends StatelessWidget {
  final bool isEs;
  final double rate;
  const _AssumptionsBox({required this.isEs, required this.rate});

  @override
  Widget build(BuildContext context) {
    final rateStr = rate.toStringAsFixed(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppTheme.infoSurface,
        border: Border.all(color: AppTheme.infoBorder),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.infoIcon, size: 18),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: Text(
              isEs
                  ? 'Supuestos: tasa hipotecaria $rateStr% a 30 años · gastos operativos 30% de la renta · costos de cierre 2% · venta con 6% de gastos.'
                  : 'Assumptions: $rateStr% mortgage rate, 30yr · 30% operating expenses · 2% closing costs · 6% selling costs at exit.',
              style: const TextStyle(
                color: AppTheme.infoText,
                fontSize: AppTextSize.sm,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Verdict legend ────────────────────────────────────────────────────────────

class _VerdictLegend extends StatelessWidget {
  final bool isEs;
  const _VerdictLegend({required this.isEs});

  @override
  Widget build(BuildContext context) {
    final items = isEs
        ? [
            ('Excelente', 'IRR > 15%', AppTheme.accentGood),
            ('Bueno', 'IRR 10–15%', const Color(0xFF2196F3)),
            ('Regular', 'IRR 6–10%', AppTheme.accentWarn),
            ('Bajo', 'IRR < 6%',
                CalcwiseSemanticColors.error(Theme.of(context).brightness)),
          ]
        : [
            ('Excellent', 'IRR > 15%', AppTheme.accentGood),
            ('Good', 'IRR 10–15%', const Color(0xFF2196F3)),
            ('Fair', 'IRR 6–10%', AppTheme.accentWarn),
            ('Poor', 'IRR < 6%',
                CalcwiseSemanticColors.error(Theme.of(context).brightness)),
          ];

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: items
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: e.$3, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text('${e.$1} ${e.$2}',
                      style: TextStyle(
                          fontSize: AppTextSize.xs,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65))),
                ],
              ))
          .toList(),
    );
  }
}

// ── Hold period toggle ────────────────────────────────────────────────────────

class _HoldPeriodToggle extends StatelessWidget {
  final int selected;
  final List<int> options;
  final bool isEs;
  final ValueChanged<int> onSelect;

  const _HoldPeriodToggle({
    required this.selected,
    required this.options,
    required this.isEs,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: options
            .map(
              (y) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _ToggleChip(
                    label: '$y ${isEs ? 'años' : 'yrs'}',
                    selected: selected == y,
                    onTap: () => onSelect(y),
                  ),
                ),
              ),
            )
            .toList(),
      );
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.mdPlus),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : CalcwiseTheme.of(context).surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : CalcwiseTheme.of(context).textPrimary,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: AppTextSize.md,
              ),
            ),
          ),
        ),
      );
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  final String labelEn, labelEs;
  final double value, min, max;
  final String valueSuffix, displayValue, minLabel, maxLabel;
  final int divisions;
  final bool isEs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.labelEn,
    required this.labelEs,
    required this.value,
    required this.valueSuffix,
    required this.displayValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.minLabel,
    required this.maxLabel,
    required this.isEs,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${isEs ? labelEs : labelEn}: '
                '${value.toStringAsFixed(1)}$valueSuffix',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: AppTextSize.bodyMd),
              ),
              Text(
                displayValue,
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppTheme.primary,
            label: '${value.toStringAsFixed(1)}$valueSuffix',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minLabel,
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                      fontSize: AppTextSize.sm)),
              Text(maxLabel,
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                      fontSize: AppTextSize.sm)),
            ],
          ),
        ],
      );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: AppTextSize.bodyMd,
              color: Theme.of(context).colorScheme.onSurface),
        ),
      );
}

// ── Result row ────────────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const _Row({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: AppTextSize.body)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color ?? (bold ? AppTheme.labelGray : null),
                fontSize: AppTextSize.body,
              ),
            ),
          ],
        ),
      );
}

// ── Verdict helpers ────────────────────────────────────────────────────────────

enum _Verdict { excellent, good, fair, poor }

_Verdict _verdict(double irr) {
  if (irr > 15) return _Verdict.excellent;
  if (irr > 10) return _Verdict.good;
  if (irr > 6) return _Verdict.fair;
  return _Verdict.poor;
}

Color _verdictColor(_Verdict v, Brightness b) => switch (v) {
      _Verdict.excellent => AppTheme.accentGood,
      _Verdict.good => const Color(0xFF2196F3),
      _Verdict.fair => AppTheme.accentWarn,
      _Verdict.poor => CalcwiseSemanticColors.error(b),
    };

IconData _verdictIcon(_Verdict v) => switch (v) {
      _Verdict.excellent => Icons.thumb_up_rounded,
      _Verdict.good => Icons.trending_up_rounded,
      _Verdict.fair => Icons.remove_rounded,
      _Verdict.poor => Icons.thumb_down_rounded,
    };

String _verdictLabel(_Verdict v, bool isEs) => switch (v) {
      _Verdict.excellent =>
        isEs ? 'Excelente — Gran inversión' : 'Excellent — Strong investment',
      _Verdict.good =>
        isEs ? 'Bueno — Inversión sólida' : 'Good — Solid investment',
      _Verdict.fair =>
        isEs ? 'Regular — Inversión moderada' : 'Fair — Moderate return',
      _Verdict.poor => isEs
          ? 'Bajo — Considerar otras opciones'
          : 'Poor — Consider alternatives',
    };

// ── Data class ────────────────────────────────────────────────────────────────

class _InvestmentResult {
  final double price;
  final double downAmt;
  final double initialInv;
  final double loanAmt;
  final double mortgageMo;
  final double monthlyCF;
  final double cashOnCash;
  final double irr;
  final double npv;
  final double equityMult;

  const _InvestmentResult({
    required this.price,
    required this.downAmt,
    required this.initialInv,
    required this.loanAmt,
    required this.mortgageMo,
    required this.monthlyCF,
    required this.cashOnCash,
    required this.irr,
    required this.npv,
    required this.equityMult,
  });
}

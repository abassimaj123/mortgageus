import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../widgets/save_scenario_button.dart';
import '../../../core/services/pdf_export_service.dart';
import '../history/history_screen.dart' show HistoryScreen;

/// HELOC Calculator
///
/// Available Equity  = Home Value × MaxLTV% − Mortgage Balance
/// Interest-Only Pmt = Draw × Rate/12
/// Repayment Pmt     = amortization(Draw, Rate, repaymentYears)
/// Total Cost        = interestOnly × drawPeriodMonths + repaymentPmt × repaymentMonths
/// LTV after draw    = (MortgageBalance + Draw) / HomeValue
class HelocCalcScreen extends ConsumerStatefulWidget {
  const HelocCalcScreen({super.key});

  @override
  ConsumerState<HelocCalcScreen> createState() => _HelocCalcScreenState();
}

class _HelocCalcScreenState extends ConsumerState<HelocCalcScreen> {
  final _homeValueCtrl = TextEditingController(text: '450,000');
  final _mortgageBalCtrl = TextEditingController(text: '280,000');
  final _drawAmountCtrl = TextEditingController(text: '50,000');
  final _rateCtrl = TextEditingController(text: '8.5');

  double _maxLtv = 85.0;
  int _drawPeriod = 10; // years
  int _repaymentPeriod = 20; // years

  bool _logged = false;

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('heloc_calc');
    AnalyticsService.instance.maybeLogFirstCalculate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pre-fill from main calculator provider
      final input = ref.read(mortgageInputProvider);
      if (input.homePrice > 0) {
        _homeValueCtrl.text = NumberFormat('#,##0').format(input.homePrice.round());
      }
      final loanBalance = input.homePrice > 0
          ? (input.homePrice * (1 - input.downPaymentPct / 100)).clamp(0.0, double.infinity)
          : 0.0;
      if (loanBalance > 0) {
        _mortgageBalCtrl.text = NumberFormat('#,##0').format(loanBalance.round());
      }
      if (input.annualRatePct > 0) {
        _rateCtrl.text = input.annualRatePct.toStringAsFixed(2);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'heloc_calc');
    _homeValueCtrl.dispose();
    _mortgageBalCtrl.dispose();
    _drawAmountCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _triggerAutoSave() {
    final homeValue = _parse(_homeValueCtrl.text);
    final mortgageBal = _parse(_mortgageBalCtrl.text);
    final drawAmount = _parse(_drawAmountCtrl.text);
    final rate = double.tryParse(_rateCtrl.text) ?? 8.5;
    if (homeValue <= 0 || drawAmount <= 0) return;
    final availableEquity = (homeValue * _maxLtv / 100.0 - mortgageBal).clamp(0.0, double.infinity);
    final monthlyInterestOnly = drawAmount * rate / 100.0 / 12.0;
    final monthlyRepayment = _amortPmt(drawAmount, rate, _repaymentPeriod);
    final totalCost = monthlyInterestOnly * _drawPeriod * 12 + monthlyRepayment * _repaymentPeriod * 12;
    _scheduleAutoSave(
      homeValue: homeValue,
      mortgageBal: mortgageBal,
      drawAmount: drawAmount,
      rate: rate,
      availableEquity: availableEquity,
      monthlyInterestOnly: monthlyInterestOnly,
      monthlyRepayment: monthlyRepayment,
      totalCost: totalCost,
    );
  }

  Future<void> _exportPdf(bool isEs) async {
    final homeValue = _parse(_homeValueCtrl.text);
    final drawAmount = _parse(_drawAmountCtrl.text);
    if (homeValue <= 0 || drawAmount <= 0) return;
    final mortgageBal = _parse(_mortgageBalCtrl.text);
    final rate = double.tryParse(_rateCtrl.text) ?? 8.5;
    final availableEquity =
        (homeValue * _maxLtv / 100.0 - mortgageBal).clamp(0.0, double.infinity);
    final monthlyInterestOnly = drawAmount * rate / 100.0 / 12.0;
    final monthlyRepayment = _amortPmt(drawAmount, rate, _repaymentPeriod);
    final totalCost = monthlyInterestOnly * _drawPeriod * 12 +
        monthlyRepayment * _repaymentPeriod * 12;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportHeloc(
        context,
        homeValue: homeValue,
        mortgageBalance: mortgageBal,
        maxLtv: _maxLtv,
        drawAmount: drawAmount,
        rate: rate,
        drawPeriod: _drawPeriod,
        repaymentPeriod: _repaymentPeriod,
        availableEquity: availableEquity,
        monthlyInterestOnly: monthlyInterestOnly,
        monthlyRepayment: monthlyRepayment,
        totalCost: totalCost,
        isEs: isEs,
      );
    });
  }

  Future<void> _onInteraction() async {
    _triggerAutoSave();
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logHelocCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  void _scheduleAutoSave({
    required double homeValue,
    required double mortgageBal,
    required double drawAmount,
    required double rate,
    required double availableEquity,
    required double monthlyInterestOnly,
    required double monthlyRepayment,
    required double totalCost,
  }) {
    if (homeValue <= 0 || drawAmount <= 0) return;
    final hash = ResultHasher.hashMixed({
      'home_value': _roundTo(homeValue, 5000),
      'mortgage_bal': _roundTo(mortgageBal, 5000),
      'draw_amount': _roundTo(drawAmount, 1000),
      'rate': _roundTo(rate, 0.25),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'mortgageus',
      screenId: 'heloc_calc',
      inputHash: hash,
      l1: {
        'home_value': homeValue,
        'available_equity': availableEquity,
        'draw_amount': drawAmount,
        'monthly_interest': monthlyInterestOnly,
      },
      l2: {
        'inputs': {
          'home_value': homeValue,
          'mortgage_balance': mortgageBal,
          'draw_amount': drawAmount,
          'rate': rate,
          'max_ltv': _maxLtv,
          'draw_period': _drawPeriod,
          'repayment_period': _repaymentPeriod,
        },
        'results': {
          'available_equity': availableEquity,
          'draw_phase_payment': monthlyInterestOnly,
          'repayment_payment': monthlyRepayment,
          'total_interest': totalCost,
        },
      },
    );
    HistoryScreen.refreshNotifier.value++;
  }

  Future<void> _saveScenario(String? label) async {
    final homeValue = _parse(_homeValueCtrl.text);
    final mortgageBal = _parse(_mortgageBalCtrl.text);
    final drawAmount = _parse(_drawAmountCtrl.text);
    final rate = double.tryParse(_rateCtrl.text) ?? 8.5;
    if (homeValue <= 0 || drawAmount <= 0) return;
    final availableEquity = (homeValue * _maxLtv / 100.0 - mortgageBal).clamp(0.0, double.infinity);
    final monthlyInterestOnly = drawAmount > 0 && rate > 0 ? drawAmount * rate / 100.0 / 12.0 : 0.0;
    final monthlyRepayment = _amortPmt(drawAmount, rate, _repaymentPeriod);
    final totalCost = monthlyInterestOnly * _drawPeriod * 12 + monthlyRepayment * _repaymentPeriod * 12;
    final hash = ResultHasher.hashMixed({
      'home_value': _roundTo(homeValue, 5000),
      'mortgage_bal': _roundTo(mortgageBal, 5000),
      'draw_amount': _roundTo(drawAmount, 1000),
      'rate': _roundTo(rate, 0.25),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'heloc_calc',
      inputHash: hash,
      l1: {
        'home_value': homeValue,
        'available_equity': availableEquity,
        'draw_amount': drawAmount,
        'monthly_interest': monthlyInterestOnly,
      },
      l2: {
        'inputs': {
          'home_value': homeValue,
          'mortgage_balance': mortgageBal,
          'draw_amount': drawAmount,
          'rate': rate,
          'max_ltv': _maxLtv,
          'draw_period': _drawPeriod,
          'repayment_period': _repaymentPeriod,
        },
        'results': {
          'available_equity': availableEquity,
          'draw_phase_payment': monthlyInterestOnly,
          'repayment_payment': monthlyRepayment,
          'total_interest': totalCost,
        },
      },
      label: freemiumService.hasFullAccess ? label : null,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  // Standard amortization monthly payment
  double _amortPmt(double principal, double annualRate, int years) {
    if (principal <= 0 || years <= 0) return 0.0;
    if (annualRate <= 0) return principal / (years * 12);
    final r = annualRate / 100.0 / 12.0;
    final n = years * 12;
    return principal * (r * math.pow(1 + r, n)) / (math.pow(1 + r, n) - 1);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        // ── Calculations ──────────────────────────────────────────────────────
        final homeValue = _parse(_homeValueCtrl.text);
        final mortgageBal = _parse(_mortgageBalCtrl.text);
        final drawAmount = _parse(_drawAmountCtrl.text);
        final rate = double.tryParse(_rateCtrl.text) ?? 8.5;

        final availableEquity = homeValue > 0
            ? (homeValue * _maxLtv / 100.0 - mortgageBal)
                .clamp(0.0, double.infinity)
            : 0.0;

        final monthlyInterestOnly =
            drawAmount > 0 && rate > 0 ? drawAmount * rate / 100.0 / 12.0 : 0.0;

        final monthlyRepayment = _amortPmt(drawAmount, rate, _repaymentPeriod);

        final totalCost = monthlyInterestOnly * _drawPeriod * 12 +
            monthlyRepayment * _repaymentPeriod * 12;

        final ltvAfterDraw = homeValue > 0
            ? (mortgageBal + drawAmount) / homeValue * 100.0
            : 0.0;

        final drawExceedsEquity = drawAmount > availableEquity;
        final ltvTooHigh = ltvAfterDraw > 90.0;

        // ─────────────────────────────────────────────────────────────────────
        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Calculadora HELOC' : 'HELOC Calculator'),
          ),
          body: Column(children: [
            Expanded(
              child: CalcwisePageEntrance(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Home Value ───────────────────────────────────────
                      _SectionLabel(
                        isEs ? 'Valor de la Vivienda' : 'Home Value',
                        Icons.home_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _homeValueCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText:
                              isEs ? 'Valor de la vivienda' : 'Home value',
                          prefixText: '\$',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _onInteraction();
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _mortgageBalCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: isEs
                              ? 'Saldo Hipotecario'
                              : 'Current Mortgage Balance',
                          prefixText: '\$',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _onInteraction();
                        },
                      ),

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Max LTV slider ───────────────────────────────────
                      _SectionLabel(
                        isEs ? 'LTV Máximo' : 'Max LTV',
                        Icons.percent_rounded,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_maxLtv.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppTextSize.bodyMd,
                                color: AppTheme.primary),
                          ),
                          if (availableEquity > 0)
                            Text(
                              '${isEs ? 'Disp:' : 'Avail:'} ${AmountFormatter.ui(availableEquity, 'USD')}',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.65)),
                            ),
                        ],
                      ),
                      Slider(
                        value: _maxLtv,
                        min: 75.0,
                        max: 90.0,
                        divisions: 15,
                        activeColor: AppTheme.primary,
                        label: '${_maxLtv.toStringAsFixed(0)}%',
                        onChanged: (v) {
                          setState(() => _maxLtv = v);
                          _onInteraction();
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('75%',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.65))),
                          Text('90%',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.65))),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Draw Amount ──────────────────────────────────────
                      _SectionLabel(
                        isEs ? 'Monto a Retirar' : 'Draw Amount',
                        Icons.account_balance_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _drawAmountCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: InputDecoration(
                              labelText:
                                  isEs ? 'Monto a retirar' : 'Draw amount',
                              prefixText: '\$',
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg)),
                            ),
                            onChanged: (_) {
                              setState(() {});
                              _onInteraction();
                            },
                          ),
                        ),
                        if (availableEquity > 0) ...[
                          const SizedBox(width: AppSpacing.sm),
                          ActionChip(
                            label: Text(
                              isEs ? 'Máximo' : 'Max Available',
                              style: const TextStyle(fontSize: AppTextSize.sm),
                            ),
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.1),
                            side: BorderSide(
                                color: AppTheme.primary.withValues(alpha: 0.3)),
                            onPressed: () {
                              _drawAmountCtrl.text = NumberFormat('#,##0')
                                  .format(availableEquity.round());
                              setState(() {});
                              _onInteraction();
                            },
                          ),
                        ],
                      ]),

                      const SizedBox(height: AppSpacing.md),

                      // ── Interest Rate ────────────────────────────────────
                      TextFormField(
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: isEs
                              ? 'Tasa de interés (%)'
                              : 'Interest Rate (%)',
                          suffixText: '%',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _onInteraction();
                        },
                      ),

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Draw Period chips ────────────────────────────────
                      _SectionLabel(
                        isEs
                            ? 'Período de Retiro (años)'
                            : 'Draw Period (years)',
                        Icons.timer_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _ChipRow(
                        options: const [5, 10],
                        selected: _drawPeriod,
                        onSelected: (v) {
                          setState(() => _drawPeriod = v);
                          _onInteraction();
                        },
                      ),

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Repayment Period chips ───────────────────────────
                      _SectionLabel(
                        isEs
                            ? 'Período de Repago (años)'
                            : 'Repayment Period (years)',
                        Icons.timelapse_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _ChipRow(
                        options: const [10, 15, 20],
                        selected: _repaymentPeriod,
                        onSelected: (v) {
                          setState(() => _repaymentPeriod = v);
                          _onInteraction();
                        },
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // ── Results ──────────────────────────────────────────
                      if (homeValue > 0 && drawAmount > 0) ...[
                        // Hero: Available Equity
                        _HeroCard(
                          label:
                              isEs ? 'Capital Disponible' : 'Available Equity',
                          value: AmountFormatter.ui(availableEquity, 'USD'),
                          icon: Icons.account_balance_rounded,
                          color: const Color(0xFF0D9488),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Secondary result cards
                        Row(children: [
                          Expanded(
                            child: _ResultMini(
                              label: isEs
                                  ? 'Pago Solo Interés'
                                  : 'Interest-Only Payment',
                              value: '${AmountFormatter.ui(monthlyInterestOnly, 'USD')}/mo',
                              color: const Color(0xFF0D9488),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _ResultMini(
                              label:
                                  isEs ? 'Pago de Repago' : 'Repayment Payment',
                              value: '${AmountFormatter.ui(monthlyRepayment, 'USD')}/mo',
                              color: AppTheme.primary,
                            ),
                          ),
                        ]),
                        const SizedBox(height: AppSpacing.sm),
                        _ResultMini(
                          label: isEs
                              ? 'Costo Total del HELOC'
                              : 'Total Cost of HELOC',
                          value: AmountFormatter.ui(totalCost, 'USD'),
                          color: AppTheme.accentWarn,
                          wide: true,
                        ),

                        const SizedBox(height: AppSpacing.sm),

                        // LTV after draw info row
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isEs
                                    ? 'LTV después del retiro'
                                    : 'LTV after draw',
                                style: TextStyle(
                                    fontSize: AppTextSize.body,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.65)),
                              ),
                              Text(
                                '${ltvAfterDraw.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppTextSize.bodyMd,
                                  color: ltvAfterDraw > 90.0
                                      ? CalcwiseSemanticColors.error(
                                          Theme.of(context).brightness)
                                      : ltvAfterDraw > 80.0
                                          ? AppTheme.accentWarn
                                          : CalcwiseSemanticColors.success(
                                              Theme.of(context).brightness),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.sm),

                        // Warning if LTV > 90%
                        if (ltvTooHigh)
                          _WarningBanner(
                            message: isEs
                                ? 'La mayoría de prestamistas requieren LTV ≤ 90%'
                                : 'Most lenders require ≤90% LTV',
                          ),

                        const SizedBox(height: AppSpacing.sm),

                        // Verdict
                        _VerdictBanner(
                          ok: !drawExceedsEquity,
                          messageOk: isEs
                              ? 'El capital de tu vivienda soporta este retiro'
                              : 'Your home equity supports this draw',
                          messageErr: isEs
                              ? 'El retiro excede el capital disponible'
                              : 'Draw exceeds available equity',
                        ),

                        const SizedBox(height: AppSpacing.md),
                        SaveScenarioButton(onSave: _saveScenario, labelEn: 'Save HELOC Result', labelEs: 'Guardar resultado HELOC'),
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
                              label: Text(isEs
                                  ? 'Exportar PDF'
                                  : 'Export PDF'),
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
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // ── Info box ─────────────────────────────────────────
                      _InfoBox(
                        text: isEs
                            ? 'Un HELOC tiene dos fases: retiro (solo interés) y repago (amortización). Las tasas son variables — esta estimación usa la tasa actual como referencia.'
                            : 'A HELOC has two phases: draw (interest-only) and repayment (amortizing). Rates are variable — this estimate uses your current rate as a reference.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
            const CalcwiseAdFooter(),
          ]),
        );
      },
    );
  }
}

// ── Shared sub-widgets ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SectionLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(text,
            style: const TextStyle(
                fontSize: AppTextSize.bodyMd,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary)),
      ]);
}

class _ChipRow extends StatelessWidget {
  final List<int> options;
  final int selected;
  final ValueChanged<int> onSelected;
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        children: options
            .map((v) => ChoiceChip(
                  label: Text('$v yr'),
                  selected: selected == v,
                  onSelected: (_) => onSelected(v),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                  side: BorderSide(
                    color: selected == v
                        ? AppTheme.primary
                        : const Color(0xFFCBD5E1),
                  ),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected == v
                        ? AppTheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                  ),
                ))
            .toList(),
      );
}

class _HeroCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _HeroCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: AppTextSize.sm)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTextSize.titleMd,
                    fontWeight: FontWeight.w800)),
          ]),
        ]),
      );
}

class _ResultMini extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool wide;
  const _ResultMini({
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: wide ? double.infinity : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65))),
            const SizedBox(height: AppSpacing.xxs),
            Text(value,
                style: TextStyle(
                    fontSize: AppTextSize.bodyMd,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      );
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: CalcwiseSemanticColors.warnBg,
          border: Border.all(color: CalcwiseSemanticColors.warnBorder),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: CalcwiseSemanticColors.warnIcon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: CalcwiseSemanticColors.warnDark,
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.w500))),
        ]),
      );
}

class _VerdictBanner extends StatelessWidget {
  final bool ok;
  final String messageOk, messageErr;
  const _VerdictBanner({
    required this.ok,
    required this.messageOk,
    required this.messageErr,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ok
              ? CalcwiseSemanticColors.successBg
              : CalcwiseSemanticColors.errorBg,
          border: Border.all(
              color: ok
                  ? CalcwiseSemanticColors.successBorder
                  : CalcwiseSemanticColors.errorBorder),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: ok
                  ? CalcwiseSemanticColors.successDark
                  : CalcwiseSemanticColors.errorDark,
              size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(ok ? messageOk : messageErr,
                  style: TextStyle(
                      color: ok
                          ? CalcwiseSemanticColors.successDark
                          : CalcwiseSemanticColors.errorDark,
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        decoration: BoxDecoration(
          color: AppTheme.infoSurface,
          border: Border.all(color: AppTheme.infoBorder),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: AppTheme.infoIcon, size: 18),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppTheme.infoText,
                      fontSize: AppTextSize.md,
                      height: 1.4))),
        ]),
      );
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/services/analytics_service.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart'
    show PaywallTrigger, CalcwiseAdFooter, CalcwisePageEntrance;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;

/// HELOC Calculator
///
/// Available Equity  = Home Value × MaxLTV% − Mortgage Balance
/// Interest-Only Pmt = Draw × Rate/12
/// Repayment Pmt     = amortization(Draw, Rate, repaymentYears)
/// Total Cost        = interestOnly × drawPeriodMonths + repaymentPmt × repaymentMonths
/// LTV after draw    = (MortgageBalance + Draw) / HomeValue
class HelocCalcScreen extends StatefulWidget {
  const HelocCalcScreen({super.key});

  @override
  State<HelocCalcScreen> createState() => _HelocCalcScreenState();
}

class _HelocCalcScreenState extends State<HelocCalcScreen> {
  final _homeValueCtrl = TextEditingController(text: '450,000');
  final _mortgageBalCtrl = TextEditingController(text: '280,000');
  final _drawAmountCtrl = TextEditingController(text: '50,000');
  final _rateCtrl = TextEditingController(text: '8.5');

  double _maxLtv = 85.0;
  int _drawPeriod = 10; // years
  int _repaymentPeriod = 20; // years

  bool _logged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
  }

  @override
  void dispose() {
    _homeValueCtrl.dispose();
    _mortgageBalCtrl.dispose();
    _drawAmountCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logHelocCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
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
            ? (homeValue * _maxLtv / 100.0 - mortgageBal).clamp(
                0.0, double.infinity)
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

        final fmt = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 0);
        final fmtDec = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 2);

        // ─────────────────────────────────────────────────────────────────────
        return Scaffold(
          appBar: AppBar(
            title: Text(
                isEs ? 'Calculadora HELOC' : 'HELOC Calculator'),
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
                              '${isEs ? 'Disp:' : 'Avail:'} ${fmt.format(availableEquity)}',
                              style: const TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: Color(0xFF64748B)),
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
                        children: const [
                          Text('75%',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: Color(0xFF64748B))),
                          Text('90%',
                              style: TextStyle(
                                  fontSize: AppTextSize.sm,
                                  color: Color(0xFF64748B))),
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
                              style:
                                  const TextStyle(fontSize: AppTextSize.sm),
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
                          labelText:
                              isEs ? 'Tasa de interés (%)' : 'Interest Rate (%)',
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
                        isEs ? 'Período de Retiro (años)' : 'Draw Period (years)',
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
                          label: isEs
                              ? 'Capital Disponible'
                              : 'Available Equity',
                          value: fmt.format(availableEquity),
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
                              value: '${fmtDec.format(monthlyInterestOnly)}/mo',
                              color: const Color(0xFF0D9488),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _ResultMini(
                              label: isEs
                                  ? 'Pago de Repago'
                                  : 'Repayment Payment',
                              value: '${fmtDec.format(monthlyRepayment)}/mo',
                              color: AppTheme.primary,
                            ),
                          ),
                        ]),
                        const SizedBox(height: AppSpacing.sm),
                        _ResultMini(
                          label: isEs
                              ? 'Costo Total del HELOC'
                              : 'Total Cost of HELOC',
                          value: fmt.format(totalCost),
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
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isEs
                                    ? 'LTV después del retiro'
                                    : 'LTV after draw',
                                style: const TextStyle(
                                    fontSize: AppTextSize.body,
                                    color: Color(0xFF64748B)),
                              ),
                              Text(
                                '${ltvAfterDraw.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppTextSize.bodyMd,
                                  color: ltvAfterDraw > 90.0
                                      ? CalcwiseSemanticColors.errorDark
                                      : ltvAfterDraw > 80.0
                                          ? AppTheme.accentWarn
                                          : CalcwiseSemanticColors.successDark,
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
                        : const Color(0xFF64748B),
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
                style: const TextStyle(
                    fontSize: AppTextSize.xs, color: Color(0xFF64748B))),
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
          Icon(
              ok
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
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

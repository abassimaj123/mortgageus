import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart'
    show adService, paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../history/history_screen.dart' show HistoryScreen;

/// VA Loan Calculator
/// 0% down allowed. No PMI. Funding fee financed into loan.
/// First-use regular 2.15%, first-use reserves/NG 2.40%, subsequent 3.30%.
class VaScreen extends ConsumerStatefulWidget {
  const VaScreen({super.key});

  @override
  ConsumerState<VaScreen> createState() => _VaScreenState();
}

class _VaScreenState extends ConsumerState<VaScreen> {
  final _homePriceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '300');
  final _insCtrl = TextEditingController(text: '120');
  double _downPct = 0.0;
  bool _reserves = false;
  bool _subsequent = false;
  bool _logged = false;

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('va');
    AnalyticsService.instance.maybeLogFirstCalculate();
    final input = ref.read(mortgageInputProvider);
    _homePriceCtrl.text = input.homePrice.toStringAsFixed(0);
    if (input.homePrice > 0) {
      final monthlyTax = input.homePrice * input.propertyTaxRatePct / 100 / 12;
      if (monthlyTax > 0) _taxCtrl.text = monthlyTax.toStringAsFixed(0);
    }
    if (input.homeInsuranceAnnual > 0) {
      _insCtrl.text = (input.homeInsuranceAnnual / 12).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'va');
    _homePriceCtrl.dispose();
    _taxCtrl.dispose();
    _insCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    // Schedule auto-save
    final price = _parse(_homePriceCtrl.text);
    if (price > 0) {
      final input = ref.read(mortgageInputProvider);
      final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
      final down = price * _downPct / 100.0;
      final baseLoan = (price - down).clamp(0.0, double.infinity);
      final ffRate = _fundingFeeRate();
      final fundingFee = baseLoan * ffRate;
      final loan = baseLoan + fundingFee;
      final term = input.termYears > 0 ? input.termYears : 30;
      final pAndI = loan > 0 ? MortgageCalculator.calcMonthlyPayment(loanAmount: loan, annualRatePct: rate, termYears: term) : 0.0;
      final tax = _parse(_taxCtrl.text);
      final ins = _parse(_insCtrl.text);
      final total = pAndI + tax + ins;
      final serviceType = _subsequent ? 'subsequent' : _reserves ? 'reserves' : 'regular';
      final hash = ResultHasher.hashMixed({
        'home_price': _roundTo(price, 5000),
        'down_pct': _roundTo(_downPct, 5.0),
        'rate': _roundTo(rate, 0.25),
        'service_type': serviceType,
      });
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'va',
        inputHash: hash,
        l1: {
          'home_price': price,
          'down_pct': _downPct,
          'rate': rate,
          'monthly_payment': total,
          'funding_fee': fundingFee,
        },
        l2: {
          'inputs': {
            'home_price': price,
            'down_pct': _downPct,
            'rate': rate,
            'service_type': serviceType,
          },
          'results': {
            'funding_fee': fundingFee,
            'loan_amount': loan,
            'monthly_payment': total,
          },
        },
      );
      HistoryScreen.refreshNotifier.value++;
    }
    adService.onAction();
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logVaCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context, isSpanish: isSpanishNotifier.value);
    if (t == PaywallTrigger.hard) PaywallHard.show(context, isSpanish: isSpanishNotifier.value);
  }

  Future<void> _saveScenario(String? label) async {
    final price = _parse(_homePriceCtrl.text);
    if (price <= 0) return;
    final input = ref.read(mortgageInputProvider);
    final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
    final down = price * _downPct / 100.0;
    final baseLoan = (price - down).clamp(0.0, double.infinity);
    final ffRate = _fundingFeeRate();
    final fundingFee = baseLoan * ffRate;
    final loan = baseLoan + fundingFee;
    final term = input.termYears > 0 ? input.termYears : 30;
    final pAndI = loan > 0 ? MortgageCalculator.calcMonthlyPayment(loanAmount: loan, annualRatePct: rate, termYears: term) : 0.0;
    final tax = _parse(_taxCtrl.text);
    final ins = _parse(_insCtrl.text);
    final total = pAndI + tax + ins;
    final serviceType = _subsequent ? 'subsequent' : _reserves ? 'reserves' : 'regular';
    final hash = ResultHasher.hashMixed({
      'home_price': _roundTo(price, 5000),
      'down_pct': _roundTo(_downPct, 5.0),
      'rate': _roundTo(rate, 0.25),
      'service_type': serviceType,
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'va',
      inputHash: hash,
      l1: {
        'home_price': price,
        'down_pct': _downPct,
        'rate': rate,
        'monthly_payment': total,
        'funding_fee': fundingFee,
      },
      l2: {
        'inputs': {
          'home_price': price,
          'down_pct': _downPct,
          'rate': rate,
          'service_type': serviceType,
        },
        'results': {
          'funding_fee': fundingFee,
          'loan_amount': loan,
          'monthly_payment': total,
        },
      },
      label: label,
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
    AnalyticsService.instance.logHistorySaved();
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  Future<void> _exportPdf(bool isEs) async {
    final price = _parse(_homePriceCtrl.text);
    if (price <= 0) return;
    final input = ref.read(mortgageInputProvider);
    final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
    final term = input.termYears > 0 ? input.termYears : 30;
    final down = price * _downPct / 100.0;
    final baseLoan = (price - down).clamp(0.0, double.infinity);
    final ffRate = _fundingFeeRate();
    final fundingFee = baseLoan * ffRate;
    final loan = baseLoan + fundingFee;
    final pAndI = loan > 0
        ? MortgageCalculator.calcMonthlyPayment(
            loanAmount: loan, annualRatePct: rate, termYears: term)
        : 0.0;
    final tax = _parse(_taxCtrl.text);
    final ins = _parse(_insCtrl.text);
    final total = pAndI + tax + ins;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportVa(
        context,
        homePrice: price,
        downPct: _downPct,
        downAmt: down,
        ffRate: ffRate,
        fundingFee: fundingFee,
        loanAmount: loan,
        rate: rate,
        termYears: term,
        reserves: _reserves,
        subsequent: _subsequent,
        pAndI: pAndI,
        propertyTax: tax,
        insurance: ins,
        totalMonthly: total,
        isEs: isEs,
      );
      AnalyticsService.instance.logPdfExported();
    });
  }

  double _fundingFeeRate() {
    // First-use (<5% down) and subsequent-use rates come from the registry.
    // The reserves/National Guard rate (0.0240) is NOT in the registry.
    if (_subsequent) return MortgageConstants.vaFundingFeeSubsequent;
    return _reserves ? 0.0240 : MortgageConstants.vaFundingFeeFirst;
  }

  @override
  Widget build(BuildContext context) {
    final mortgageInput = ref.watch(mortgageInputProvider);
    final rate = mortgageInput.annualRatePct > 0 ? mortgageInput.annualRatePct : 7.0;
    final term = mortgageInput.termYears > 0 ? mortgageInput.termYears : 30;
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final price = _parse(_homePriceCtrl.text);
        final down = price * _downPct / 100.0;
        final baseLoan = (price - down).clamp(0.0, double.infinity);
        final ffRate = _fundingFeeRate();
        final fundingFee = baseLoan * ffRate;
        final loan = baseLoan + fundingFee; // financed
        final pAndI = loan > 0
            ? MortgageCalculator.calcMonthlyPayment(
                loanAmount: loan, annualRatePct: rate, termYears: term)
            : 0.0;
        final tax = _parse(_taxCtrl.text);
        final ins = _parse(_insCtrl.text);
        final total = pAndI + tax + ins;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Préstamo VA' : 'VA Loan'),
          ),
          body: Column(children: [
            Expanded(
              child: CalcwisePageEntrance(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _homePriceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText:
                              isEs ? 'Precio de la vivienda' : 'Home Price',
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
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              isEs
                                  ? 'Pago inicial: ${_downPct.toStringAsFixed(1)}%'
                                  : 'Down Payment: ${_downPct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: AppTextSize.bodyMd)),
                          Text(AmountFormatter.ui(down, 'USD'),
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: _downPct,
                        min: 0.0,
                        max: 25.0,
                        divisions: 250,
                        activeColor: AppTheme.primary,
                        onChanged: (v) => setState(() => _downPct = v),
                        onChangeEnd: (_) => _onInteraction(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _reserves,
                        onChanged: (v) {
                          setState(() => _reserves = v);
                          _onInteraction();
                        },
                        title: Text(isEs
                            ? 'Reservas / Guardia Nacional'
                            : 'Reserves / National Guard'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _subsequent,
                        onChanged: (v) {
                          setState(() => _subsequent = v);
                          _onInteraction();
                        },
                        title: Text(isEs
                            ? 'Uso subsiguiente del beneficio VA'
                            : 'Subsequent VA loan use'),
                      ),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: _taxCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: InputDecoration(
                              labelText:
                                  isEs ? 'Impuesto/mes' : 'Property Tax/mo',
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
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            controller: _insCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: InputDecoration(
                              labelText: isEs ? 'Seguro/mes' : 'Insurance/mo',
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
                      ]),
                      const SizedBox(height: AppSpacing.xl),
                      AnimatedSwitcher(
                        duration: AppDuration.base,
                        child: price <= 0
                            ? Center(
                                key: const ValueKey('empty'),
                                child: Text(
                                    isEs
                                        ? 'Ingresa un precio válido'
                                        : 'Enter a valid home price',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65))))
                            : Card(
                                key: const ValueKey('res'),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  side: BorderSide(
                                      color: Theme.of(context)
                                          .dividerColor
                                          .withValues(alpha: 0.4)),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xl),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Column(children: [
                                    _Row(
                                        label: isEs
                                            ? 'Tarifa de financiación'
                                            : 'Funding Fee Rate',
                                        value:
                                            '${(ffRate * 100).toStringAsFixed(2)}%'),
                                    _Row(
                                        label: isEs
                                            ? 'Tarifa de financiación \$'
                                            : 'Funding Fee \$',
                                        value: AmountFormatter.ui(fundingFee, 'USD'),
                                        color: CalcwiseSemanticColors.alert(
                                            Theme.of(context).brightness)),
                                    _Row(
                                        label: isEs
                                            ? 'Monto del préstamo (con tarifa)'
                                            : 'Loan Amount (incl. fee)',
                                        value: AmountFormatter.ui(loan, 'USD')),
                                    _Row(
                                        label: isEs
                                            ? 'Capital + Interés'
                                            : 'P & I',
                                        value: AmountFormatter.ui(pAndI, 'USD')),
                                    const Divider(height: 24),
                                    _Row(
                                        label: isEs
                                            ? 'Pago total mensual'
                                            : 'Total Monthly Payment',
                                        value: AmountFormatter.ui(total, 'USD'),
                                        bold: true,
                                        color: AppTheme.primary),
                                    const SizedBox(height: AppRadius.sm),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                          AppSpacing.smPlus),
                                      decoration: BoxDecoration(
                                        color: CalcwiseSemanticColors.successBg,
                                        border: Border.all(
                                            color: CalcwiseSemanticColors
                                                .successBorder),
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.mdPlus),
                                      ),
                                      child: Row(children: [
                                        Icon(Icons.check_circle_outline,
                                            color: CalcwiseSemanticColors
                                                .successDeep,
                                            size: 18),
                                        const SizedBox(width: AppSpacing.sm),
                                        Text(
                                            isEs
                                                ? 'Sin PMI — beneficio VA'
                                                : 'No PMI — VA benefit',
                                            style: TextStyle(
                                                color: CalcwiseSemanticColors
                                                    .successDark,
                                                fontWeight: FontWeight.w600,
                                                fontSize: AppTextSize.md)),
                                      ]),
                                    ),
                                  ]),
                                ),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (price > 0) ...[
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
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Container(
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
                            Icon(Icons.info_outline,
                                color: AppTheme.infoIcon, size: 18),
                            const SizedBox(width: AppSpacing.smPlus),
                            Expanded(
                              child: Text(
                                isEs
                                    ? 'Préstamos VA: 0% inicial, sin PMI. Tarifa: 2.15% primer uso regular, 2.40% reservas, 3.30% uso subsiguiente.'
                                    : 'VA loans: 0% down allowed, no PMI required. Funding fee: 2.15% first-use regular, 2.40% reserves/NG, 3.30% subsequent use.',
                                style: const TextStyle(
                                    color: AppTheme.infoText,
                                    fontSize: AppTextSize.md,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart'
    show adService, paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../history/history_screen.dart' show HistoryScreen;

/// USDA Loan Calculator
/// 0% down. Upfront guarantee fee = 1% (financed). Annual fee 0.35%.
/// Income limit = 115% of area median income (default $90k AMI).
class UsdaScreen extends ConsumerStatefulWidget {
  const UsdaScreen({super.key});

  @override
  ConsumerState<UsdaScreen> createState() => _UsdaScreenState();
}

class _UsdaScreenState extends ConsumerState<UsdaScreen> {
  final _homePriceCtrl = TextEditingController(text: '280000');
  final _incomeCtrl = TextEditingController(text: '75000');
  final _taxCtrl = TextEditingController(text: '220');
  final _insCtrl = TextEditingController(text: '95');
  bool _rural = true; // rural = eligible, suburban = warning
  bool _logged = false;

  static const double _defaultAmi = 90000.0;
  static const double _incomeLimit = 1.15; // 115%

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('usda');
    AnalyticsService.instance.maybeLogFirstCalculate();
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'usda');
    _homePriceCtrl.dispose();
    _incomeCtrl.dispose();
    _taxCtrl.dispose();
    _insCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    // Schedule auto-save
    final price = _parse(_homePriceCtrl.text);
    final income = _parse(_incomeCtrl.text);
    if (price > 0) {
      final input = ref.read(mortgageInputProvider);
      final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
      final term = input.termYears > 0 ? input.termYears : 30;
      final baseLoan = price;
      final upfrontFee = baseLoan * 0.01;
      final loan = baseLoan + upfrontFee;
      final annualFee = loan * 0.0035;
      final monthlyFee = annualFee / 12.0;
      final pAndI = loan > 0 ? MortgageCalculator.calcMonthlyPayment(loanAmount: loan, annualRatePct: rate, termYears: term) : 0.0;
      final tax = _parse(_taxCtrl.text);
      final ins = _parse(_insCtrl.text);
      final total = pAndI + monthlyFee + tax + ins;
      final monthlyIncome = income / 12;
      final dti = monthlyIncome > 0 ? (total / monthlyIncome) * 100 : 0.0;
      final hash = ResultHasher.hashMixed({
        'home_price': _roundTo(price, 5000),
        'income': _roundTo(income, 5000),
        'rate': _roundTo(rate, 0.25),
      });
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'usda',
        inputHash: hash,
        l1: {
          'home_price': price,
          'income': income,
          'monthly_payment': total,
          'guarantee_fee': upfrontFee,
        },
        l2: {
          'inputs': {
            'home_price': price,
            'income': income,
            'rate': rate,
          },
          'results': {
            'guarantee_fee': upfrontFee,
            'monthly_payment': total,
            'total_loan': loan,
            'dti': dti,
          },
        },
      );
      HistoryScreen.refreshNotifier.value++;
    }
    adService.onAction();
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logUsdaCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  Future<void> _saveScenario(String? label) async {
    final price = _parse(_homePriceCtrl.text);
    if (price <= 0) return;
    final income = _parse(_incomeCtrl.text);
    final input = ref.read(mortgageInputProvider);
    final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
    final term = input.termYears > 0 ? input.termYears : 30;
    final baseLoan = price;
    final upfrontFee = baseLoan * 0.01;
    final loan = baseLoan + upfrontFee;
    final annualFee = loan * 0.0035;
    final monthlyFee = annualFee / 12.0;
    final pAndI = loan > 0 ? MortgageCalculator.calcMonthlyPayment(loanAmount: loan, annualRatePct: rate, termYears: term) : 0.0;
    final tax = _parse(_taxCtrl.text);
    final ins = _parse(_insCtrl.text);
    final total = pAndI + monthlyFee + tax + ins;
    final monthlyIncome = income / 12;
    final dti = monthlyIncome > 0 ? (total / monthlyIncome) * 100 : 0.0;
    final hash = ResultHasher.hashMixed({
      'home_price': _roundTo(price, 5000),
      'income': _roundTo(income, 5000),
      'rate': _roundTo(rate, 0.25),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'usda',
      inputHash: hash,
      l1: {
        'home_price': price,
        'income': income,
        'monthly_payment': total,
        'guarantee_fee': upfrontFee,
      },
      l2: {
        'inputs': {
          'home_price': price,
          'income': income,
          'rate': rate,
        },
        'results': {
          'guarantee_fee': upfrontFee,
          'monthly_payment': total,
          'total_loan': loan,
          'dti': dti,
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
    final income = _parse(_incomeCtrl.text);
    final input = ref.read(mortgageInputProvider);
    final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
    final term = input.termYears > 0 ? input.termYears : 30;
    const maxIncome = _defaultAmi * _incomeLimit;
    final incomeOk = income > 0 && income <= maxIncome;
    final upfrontFee = price * 0.01;
    final loan = price + upfrontFee;
    final annualFee = loan * 0.0035;
    final monthlyFee = annualFee / 12.0;
    final pAndI = MortgageCalculator.calcMonthlyPayment(
        loanAmount: loan, annualRatePct: rate, termYears: term);
    final tax = _parse(_taxCtrl.text);
    final ins = _parse(_insCtrl.text);
    final total = pAndI + monthlyFee + tax + ins;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportUsda(
        context,
        homePrice: price,
        income: income,
        rate: rate,
        termYears: term,
        ruralEligible: _rural,
        incomeOk: incomeOk,
        maxIncome: maxIncome,
        upfrontFee: upfrontFee,
        loanAmount: loan,
        monthlyAnnualFee: monthlyFee,
        pAndI: pAndI,
        propertyTax: tax,
        insurance: ins,
        totalMonthly: total,
        isEs: isEs,
      );
      AnalyticsService.instance.logPdfExported();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final input = ref.watch(mortgageInputProvider);
        final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
        final term = input.termYears > 0 ? input.termYears : 30;
        final price = _parse(_homePriceCtrl.text);
        final income = _parse(_incomeCtrl.text);
        final maxIncome = _defaultAmi * _incomeLimit;
        final incomeOk = income > 0 && income <= maxIncome;

        final baseLoan = price; // 0% down
        final upfrontFee = baseLoan * 0.01;
        final loan = baseLoan + upfrontFee;
        final annualFee = loan * 0.0035;
        final monthlyFee = annualFee / 12.0;
        final pAndI = loan > 0
            ? MortgageCalculator.calcMonthlyPayment(
                loanAmount: loan, annualRatePct: rate, termYears: term)
            : 0.0;
        final tax = _parse(_taxCtrl.text);
        final ins = _parse(_insCtrl.text);
        final total = pAndI + monthlyFee + tax + ins;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Préstamo USDA' : 'USDA Loan'),
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
                      const SizedBox(height: AppSpacing.mdPlus),
                      TextFormField(
                        controller: _incomeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: isEs
                              ? 'Ingreso anual del hogar'
                              : 'Annual Household Income',
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rural,
                        onChanged: (v) {
                          setState(() => _rural = v);
                          _onInteraction();
                        },
                        title: Text(isEs
                            ? 'Zona rural elegible'
                            : 'Rural area (USDA-eligible)'),
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
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                          AppSpacing.smPlus),
                                      decoration: BoxDecoration(
                                        color: (incomeOk && _rural)
                                            ? CalcwiseSemanticColors.successBg
                                            : CalcwiseSemanticColors.alertBg,
                                        border: Border.all(
                                            color: (incomeOk && _rural)
                                                ? CalcwiseSemanticColors
                                                    .successBorder
                                                : CalcwiseSemanticColors
                                                    .alertBorder),
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.mdPlus),
                                      ),
                                      child: Row(children: [
                                        Icon(
                                            (incomeOk && _rural)
                                                ? Icons.check_circle_outline
                                                : Icons.warning_amber_rounded,
                                            color: (incomeOk && _rural)
                                                ? CalcwiseSemanticColors
                                                    .successDeep
                                                : CalcwiseSemanticColors
                                                    .warnIcon,
                                            size: 18),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: Text(
                                              (incomeOk && _rural)
                                                  ? (isEs
                                                      ? 'Elegible (límite ${AmountFormatter.ui(maxIncome, 'USD')})'
                                                      : 'Eligible (limit ${AmountFormatter.ui(maxIncome, 'USD')})')
                                                  : !_rural
                                                      ? (isEs
                                                          ? 'Zona no elegible'
                                                          : 'Area not eligible')
                                                      : (isEs
                                                          ? 'Ingreso supera ${AmountFormatter.ui(maxIncome, 'USD')}'
                                                          : 'Income exceeds ${AmountFormatter.ui(maxIncome, 'USD')}'),
                                              style: TextStyle(
                                                  color: (incomeOk && _rural)
                                                      ? CalcwiseSemanticColors
                                                          .successDark
                                                      : CalcwiseSemanticColors
                                                          .warnIcon,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: AppTextSize.md)),
                                        ),
                                      ]),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    _Row(
                                        label: isEs
                                            ? 'Tarifa garantía inicial (1%)'
                                            : 'Upfront Guarantee Fee (1%)',
                                        value: AmountFormatter.ui(upfrontFee, 'USD')),
                                    _Row(
                                        label: isEs
                                            ? 'Monto del préstamo'
                                            : 'Loan Amount',
                                        value: AmountFormatter.ui(loan, 'USD')),
                                    _Row(
                                        label: isEs
                                            ? 'Tarifa anual mensualizada (0.35%)'
                                            : 'Monthly Annual Fee (0.35%)',
                                        value: AmountFormatter.ui(monthlyFee, 'USD'),
                                        color: CalcwiseSemanticColors.alert(
                                            Theme.of(context).brightness)),
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
                                    ? 'USDA: 0% inicial, tarifa garantía 1% financiada, tarifa anual 0.35%. Límite de ingreso 115% del AMI (predeterminado \$90k).'
                                    : 'USDA: 0% down, 1% upfront guarantee fee financed, 0.35% annual fee. Income limit 115% of area median (\$90k default AMI).',
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

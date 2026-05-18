import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/services/analytics_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart'
    show PaywallTrigger, CalcwiseAdFooter, CalcwisePageEntrance;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;

/// VA Loan Calculator
/// 0% down allowed. No PMI. Funding fee financed into loan.
/// First-use regular 2.15%, first-use reserves/NG 2.40%, subsequent 3.30%.
class VaScreen extends StatefulWidget {
  const VaScreen({super.key});

  @override
  State<VaScreen> createState() => _VaScreenState();
}

class _VaScreenState extends State<VaScreen> {
  final _homePriceCtrl = TextEditingController(text: '350000');
  final _taxCtrl = TextEditingController(text: '300');
  final _insCtrl = TextEditingController(text: '120');
  double _downPct = 0.0;
  bool _reserves = false;
  bool _subsequent = false;
  bool _logged = false;

  static const double _rate = 7.0;
  static const int _term = 30;

  @override
  void dispose() {
    _homePriceCtrl.dispose();
    _taxCtrl.dispose();
    _insCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logVaCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  double _fundingFeeRate() {
    if (_subsequent) return 0.0330;
    return _reserves ? 0.0240 : 0.0215;
  }

  @override
  Widget build(BuildContext context) {
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
                loanAmount: loan, annualRatePct: _rate, termYears: _term)
            : 0.0;
        final tax = _parse(_taxCtrl.text);
        final ins = _parse(_insCtrl.text);
        final total = pAndI + tax + ins;

        final fmt = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 2);
        final fmtWhole = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 0);

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
                          Text(fmtWhole.format(down),
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
                                    style: const TextStyle(
                                        color: Color(0xFF64748B))))
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
                                        value: fmtWhole.format(fundingFee),
                                        color: Colors.orange.shade800),
                                    _Row(
                                        label: isEs
                                            ? 'Monto del préstamo (con tarifa)'
                                            : 'Loan Amount (incl. fee)',
                                        value: fmtWhole.format(loan)),
                                    _Row(
                                        label: isEs
                                            ? 'Capital + Interés'
                                            : 'P & I',
                                        value: fmt.format(pAndI)),
                                    const Divider(height: 24),
                                    _Row(
                                        label: isEs
                                            ? 'Pago total mensual'
                                            : 'Total Monthly Payment',
                                        value: fmt.format(total),
                                        bold: true,
                                        color: AppTheme.primary),
                                    const SizedBox(height: AppRadius.sm),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                          AppSpacing.smPlus),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        border: Border.all(
                                            color: CalcwiseSemanticColors.successBorder),
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.mdPlus),
                                      ),
                                      child: Row(children: [
                                        Icon(Icons.check_circle_outline,
                                            color: CalcwiseSemanticColors.successDeep,
                                            size: 18),
                                        const SizedBox(width: AppSpacing.sm),
                                        Text(
                                            isEs
                                                ? 'Sin PMI — beneficio VA'
                                                : 'No PMI — VA benefit',
                                            style: TextStyle(
                                                color: CalcwiseSemanticColors.successDark,
                                                fontWeight: FontWeight.w600,
                                                fontSize: AppTextSize.md)),
                                      ]),
                                    ),
                                  ]),
                                ),
                              ),
                      ),
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
                  style: const TextStyle(
                      color: Color(0xFF334155), fontSize: AppTextSize.body)),
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

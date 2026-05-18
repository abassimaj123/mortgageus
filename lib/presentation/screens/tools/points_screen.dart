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

/// Points / Discount Calculator
/// Each point = 1% of loan, lowers rate by ~0.25%.
/// Breakeven months = points_cost / monthly_savings.
class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final _loanCtrl = TextEditingController(text: '350000');
  final _rateCtrl = TextEditingController(text: '7.0');
  double _points = 1.0;
  int _term = 30;
  bool _logged = false;

  static const double _ratePerPoint = 0.25;

  @override
  void dispose() {
    _loanCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logPointsCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final loan = _parse(_loanCtrl.text);
        final origRate = double.tryParse(_rateCtrl.text) ?? 7.0;
        final newRate =
            (origRate - _points * _ratePerPoint).clamp(0.0, double.infinity);
        final pointsCost = loan * _points / 100.0;
        final origPay = loan > 0
            ? MortgageCalculator.calcMonthlyPayment(
                loanAmount: loan, annualRatePct: origRate, termYears: _term)
            : 0.0;
        final newPay = loan > 0
            ? MortgageCalculator.calcMonthlyPayment(
                loanAmount: loan, annualRatePct: newRate, termYears: _term)
            : 0.0;
        final monthlySav = origPay - newPay;
        final breakeven = monthlySav > 0 ? pointsCost / monthlySav : null;
        final lifetimeSav = monthlySav * _term * 12 - pointsCost;

        final fmt = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 2);
        final fmtWhole = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 0);

        String breakevenStr() {
          if (breakeven == null) return isEs ? 'N/A' : 'N/A';
          final m = breakeven.ceil();
          return '${m ~/ 12}${isEs ? ' años' : ' yrs'} ${m % 12}${isEs ? ' meses' : ' mo'}';
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Puntos de descuento' : 'Discount Points'),
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
                        controller: _loanCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText:
                              isEs ? 'Monto del préstamo' : 'Loan Amount',
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
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText:
                              isEs ? 'Tasa original %' : 'Original Rate %',
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
                      Text(
                          isEs
                              ? 'Puntos: ${_points.toStringAsFixed(2)}'
                              : 'Points: ${_points.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd)),
                      Slider(
                        value: _points,
                        min: 0.0,
                        max: 4.0,
                        divisions: 16,
                        activeColor: AppTheme.primary,
                        label: _points.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _points = v),
                        onChangeEnd: (_) => _onInteraction(),
                      ),
                      Wrap(spacing: 8, children: [
                        for (final t in const [15, 20, 30])
                          ChoiceChip(
                            label: Text('$t yr'),
                            selected: _term == t,
                            onSelected: (_) {
                              setState(() => _term = t);
                              _onInteraction();
                            },
                          ),
                      ]),
                      const SizedBox(height: AppSpacing.xl),
                      AnimatedSwitcher(
                        duration: AppDuration.base,
                        child: loan <= 0
                            ? Center(
                                key: const ValueKey('empty'),
                                child: Text(
                                    isEs
                                        ? 'Ingresa monto válido'
                                        : 'Enter a valid loan amount',
                                    style: const TextStyle(
                                        color: Color(0xFF64748B))))
                            : Card(
                                key: ValueKey('res-$_points-$_term'),
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
                                            ? 'Costo de los puntos'
                                            : 'Points Cost',
                                        value: fmtWhole.format(pointsCost),
                                        color:
                                            CalcwiseSemanticColors.alertText),
                                    _Row(
                                        label: isEs ? 'Tasa nueva' : 'New Rate',
                                        value:
                                            '${newRate.toStringAsFixed(3)}%'),
                                    _Row(
                                        label: isEs
                                            ? 'Pago original'
                                            : 'Original Payment',
                                        value: fmt.format(origPay)),
                                    _Row(
                                        label:
                                            isEs ? 'Pago nuevo' : 'New Payment',
                                        value: fmt.format(newPay)),
                                    _Row(
                                        label: isEs
                                            ? 'Ahorro mensual'
                                            : 'Monthly Savings',
                                        value: fmt.format(monthlySav),
                                        bold: true,
                                        color: AppTheme.accentGood),
                                    const Divider(height: 24),
                                    _Row(
                                        label: isEs
                                            ? 'Punto de equilibrio'
                                            : 'Breakeven',
                                        value: breakevenStr(),
                                        bold: true),
                                    _Row(
                                        label: isEs
                                            ? 'Ahorro neto ($_term años)'
                                            : 'Net Savings ($_term yrs)',
                                        value: fmtWhole.format(lifetimeSav),
                                        bold: true,
                                        color: lifetimeSav >= 0
                                            ? AppTheme.accentGood
                                            : CalcwiseSemanticColors.errorDark),
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
                                    ? 'Cada punto = 1% del préstamo y reduce la tasa ~0.25%. Comprar puntos rinde si planeas quedarte más tiempo que el punto de equilibrio.'
                                    : 'Each point = 1% of loan and lowers rate by ~0.25%. Buying points pays off only if you stay past the breakeven.',
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

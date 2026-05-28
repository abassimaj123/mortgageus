import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/services/analytics_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;

class PmiScreen extends ConsumerStatefulWidget {
  const PmiScreen({super.key});

  @override
  ConsumerState<PmiScreen> createState() => _PmiScreenState();
}

class _PmiScreenState extends ConsumerState<PmiScreen> {
  final _homePriceCtrl = TextEditingController(text: '400000');
  double _downPct = 10.0;
  bool _analyticsLogged = false;

  static const double _pmiAnnualRate = 0.80; // 0.80% — matches app-wide default

  Future<void> _onInteraction() async {
    if (!_analyticsLogged) {
      _analyticsLogged = true;
      AnalyticsService.instance.logPmiCalculated();
      final trigger = await paywallSession.recordAction();
      if (mounted) {
        if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
        if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
      }
    }
  }

  @override
  void dispose() {
    _homePriceCtrl.dispose();
    super.dispose();
  }

  // Returns how many months until LTV hits 78% (auto-cancel), or null if never
  int? _monthsUntilPmiDrop({
    required double loanAmount,
    required double homePrice,
    required double annualRatePct,
    required int termYears,
  }) {
    if (homePrice <= 0) return null;
    final targetBalance = homePrice * MortgageConstants.pmiAutoCancelLtv;
    if (loanAmount <= targetBalance) return null;

    final n = termYears * 12;
    final r = annualRatePct / 100.0 / 12.0;
    final payment = MortgageCalculator.calcMonthlyPayment(
      loanAmount: loanAmount,
      annualRatePct: annualRatePct,
      termYears: termYears,
    );

    double balance = loanAmount;
    for (int m = 1; m <= n; m++) {
      final interest = balance * r;
      final principal = (payment - interest).clamp(0.0, balance);
      balance -= principal;
      if (balance <= targetBalance) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final rawPrice = double.tryParse(
                _homePriceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
            0.0;
        final downAmt = rawPrice * _downPct / 100.0;
        final loan = (rawPrice - downAmt).clamp(0.0, double.infinity);
        final ltv = rawPrice > 0 ? (loan / rawPrice) * 100.0 : 0.0;
        final hasPmi = ltv > 80.0;

        final monthlyPmi = hasPmi
            ? MortgageCalculator.calcPmiMonthly(
                loanAmount: loan,
                homePrice: rawPrice,
                pmiAnnualRatePct: _pmiAnnualRate,
              )
            : 0.0;

        // Months until PMI auto-cancel (use current market rate as proxy)
        final int? dropMonth = hasPmi
            ? _monthsUntilPmiDrop(
                loanAmount: loan,
                homePrice: rawPrice,
                annualRatePct: MortgageConstants.defaultInterestRate,
                termYears: MortgageConstants.defaultTermYears,
              )
            : null;

        final totalPmiCost = (dropMonth != null) ? monthlyPmi * dropMonth : 0.0;



        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Calculadora PMI' : 'PMI Calculator'),
          ),
          body: Column(children: [
            Expanded(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Home Price ─────────────────────────────────────────────
                  TextFormField(
                    controller: _homePriceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: InputDecoration(
                      labelText: isEs ? 'Precio de la vivienda' : 'Home Price',
                      prefixText: '\$',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.mdPlus),
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _onInteraction();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Down Payment slider ────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEs
                            ? 'Pago inicial: ${_downPct.toStringAsFixed(1)}%'
                            : 'Down Payment: ${_downPct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: AppTextSize.bodyMd),
                      ),
                      Text(
                        AmountFormatter.format(downAmt, 'USD'),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: _downPct,
                    min: 3.0,
                    max: 25.0,
                    divisions: 220,
                    activeColor: AppTheme.primary,
                    label: '${_downPct.toStringAsFixed(1)}%',
                    onChanged: (v) => setState(() => _downPct = v),
                    onChangeEnd: (_) => _onInteraction(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('3%',
                          style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: AppTextSize.sm)),
                      Text('25%',
                          style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: AppTextSize.sm)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Results ────────────────────────────────────────────────
                  if (rawPrice <= 0)
                    Center(
                      child: Text(
                        isEs
                            ? 'Ingresa un precio válido'
                            : 'Enter a valid home price',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    )
                  else if (!hasPmi)
                    _NoPmiBadge(isEs: isEs)
                  else
                    _PmiResultsCard(
                      isEs: isEs,
                      ltv: ltv,
                      monthlyPmi: monthlyPmi,
                      dropMonth: dropMonth,
                      totalPmiCost: totalPmiCost,
                    ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Info box ───────────────────────────────────────────────
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
                                ? 'El PMI generalmente cuesta entre 0.5% y 1.5% del préstamo al año (estimación: 0.80%). Se cancela automáticamente cuando el LTV llega al 78%.'
                                : 'PMI typically costs 0.5%–1.5% of your loan annually (default estimate: 0.80%). Auto-cancelled when LTV reaches 78%.',
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
            )),
            const CalcwiseAdFooter(),
          ]),
        );
      },
    );
  }
}

// ── No PMI badge ──────────────────────────────────────────────────────────────

class _NoPmiBadge extends StatelessWidget {
  final bool isEs;
  const _NoPmiBadge({required this.isEs});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: CalcwiseSemanticColors.successBg,
          border: Border.all(color: CalcwiseSemanticColors.successBorder),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: CalcwiseSemanticColors.successDeep, size: 24),
            const SizedBox(width: AppSpacing.md),
            Text(
              isEs ? 'No se requiere PMI' : 'No PMI Required',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: CalcwiseSemanticColors.successDark,
                fontSize: AppTextSize.bodyLg,
              ),
            ),
          ],
        ),
      );
}

// ── PMI results card ──────────────────────────────────────────────────────────

class _PmiResultsCard extends StatelessWidget {
  final bool isEs;
  final double ltv;
  final double monthlyPmi;
  final int? dropMonth;
  final double totalPmiCost;

  const _PmiResultsCard({
    required this.isEs,
    required this.ltv,
    required this.monthlyPmi,
    required this.dropMonth,
    required this.totalPmiCost,
  });

  @override
  Widget build(BuildContext context) {
    final yearsMonths = dropMonth != null
        ? '${dropMonth! ~/ 12}${isEs ? ' años' : ' yrs'} ${dropMonth! % 12}${isEs ? ' meses' : ' mo'}'
        : (isEs ? 'N/A' : 'N/A');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            _Row(
              label: isEs ? 'Relación LTV' : 'LTV Ratio',
              value: '${ltv.toStringAsFixed(1)}%',
              color: ltv > 95
                  ? CalcwiseSemanticColors.errorDark
                  : ltv > 80
                      ? CalcwiseSemanticColors.warnIcon
                      : AppTheme.accentGood,
            ),
            _Row(
              label: isEs
                  ? 'PMI mensual estimado (0.80%)'
                  : 'Est. Monthly PMI (0.80%)',
              value: AmountFormatter.format(monthlyPmi, 'USD'),
              bold: true,
              color: CalcwiseSemanticColors.warnIcon,
            ),
            const Divider(height: 24),
            _Row(
              label: isEs
                  ? 'PMI se cancela en (LTV 78%)'
                  : 'PMI drops at (LTV 78%)',
              value: yearsMonths,
            ),
            if (dropMonth != null)
              _Row(
                label: isEs
                    ? 'Costo total PMI hasta cancelación'
                    : 'Total PMI cost until auto-cancel',
                value: AmountFormatter.format(totalPmiCost, 'USD'),
                bold: true,
              ),
          ],
        ),
      ),
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

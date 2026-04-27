import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/freemium/paywall_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../../main.dart' show isSpanishNotifier;
import '../../../presentation/widgets/paywall_soft.dart';
import '../../../presentation/widgets/paywall_hard.dart';

class PmiScreen extends ConsumerStatefulWidget {
  const PmiScreen({super.key});

  @override
  ConsumerState<PmiScreen> createState() => _PmiScreenState();
}

class _PmiScreenState extends ConsumerState<PmiScreen> {
  final _homePriceCtrl = TextEditingController(text: '400000');
  double _downPct = 10.0;
  bool _analyticsLogged = false;

  static const double _pmiAnnualRate = 0.85; // 0.85% default

  void _onInteraction() {
    if (!_analyticsLogged) {
      _analyticsLogged = true;
      AnalyticsService.instance.logPmiCalculated();
      final trigger = paywallService.recordAction();
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
    required int    termYears,
  }) {
    if (homePrice <= 0) return null;
    final targetBalance = homePrice * MortgageConstants.pmiAutoCancelLtv;
    if (loanAmount <= targetBalance) return null;

    final n = termYears * 12;
    final r = annualRatePct / 100.0 / 12.0;
    final payment = MortgageCalculator.calcMonthlyPayment(
      loanAmount:    loanAmount,
      annualRatePct: annualRatePct,
      termYears:     termYears,
    );

    double balance = loanAmount;
    for (int m = 1; m <= n; m++) {
      final interest  = balance * r;
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
        final downAmt  = rawPrice * _downPct / 100.0;
        final loan     = (rawPrice - downAmt).clamp(0.0, double.infinity);
        final ltv      = rawPrice > 0 ? (loan / rawPrice) * 100.0 : 0.0;
        final hasPmi   = ltv > 80.0;

        final monthlyPmi = hasPmi
            ? MortgageCalculator.calcPmiMonthly(
                loanAmount:       loan,
                homePrice:        rawPrice,
                pmiAnnualRatePct: _pmiAnnualRate,
              )
            : 0.0;

        // Months until PMI auto-cancel (use current market rate as proxy)
        final int? dropMonth = hasPmi
            ? _monthsUntilPmiDrop(
                loanAmount:    loan,
                homePrice:     rawPrice,
                annualRatePct: MortgageConstants.defaultInterestRate,
                termYears:     MortgageConstants.defaultTermYears,
              )
            : null;

        final totalPmiCost =
            (dropMonth != null) ? monthlyPmi * dropMonth : 0.0;

        final fmt = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 2);
        final fmtWhole = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 0);

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Calculadora PMI' : 'PMI Calculator'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Home Price ─────────────────────────────────────────────
                TextField(
                  controller: _homePriceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: isEs ? 'Precio de la vivienda' : 'Home Price',
                    prefixText: '\$',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _onInteraction();
                  },
                ),
                const SizedBox(height: 20),

                // ── Down Payment slider ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEs
                          ? 'Pago inicial: ${_downPct.toStringAsFixed(1)}%'
                          : 'Down Payment: ${_downPct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      fmtWhole.format(downAmt),
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
                            color: Colors.grey.shade500, fontSize: 12)),
                    Text('25%',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Results ────────────────────────────────────────────────
                if (rawPrice <= 0)
                  Center(
                    child: Text(
                      isEs
                          ? 'Ingresa un precio válido'
                          : 'Enter a valid home price',
                      style: TextStyle(color: Colors.grey.shade500),
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
                    fmt: fmt,
                    fmtWhole: fmtWhole,
                  ),

                const SizedBox(height: 20),

                // ── Info box ───────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEs
                              ? 'El PMI generalmente cuesta entre 0.5% y 1.5% del préstamo al año. Se cancela automáticamente cuando tu LTV llega al 78%.'
                              : 'PMI typically costs 0.5%–1.5% of your loan annually. It\'s automatically cancelled when your LTV reaches 78%.',
                          style: TextStyle(
                              color: Colors.blue.shade900,
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border.all(color: Colors.green.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green.shade700, size: 24),
            const SizedBox(width: 12),
            Text(
              isEs ? 'No se requiere PMI' : 'No PMI Required',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
}

// ── PMI results card ──────────────────────────────────────────────────────────

class _PmiResultsCard extends StatelessWidget {
  final bool         isEs;
  final double       ltv;
  final double       monthlyPmi;
  final int?         dropMonth;
  final double       totalPmiCost;
  final NumberFormat fmt;
  final NumberFormat fmtWhole;

  const _PmiResultsCard({
    required this.isEs,
    required this.ltv,
    required this.monthlyPmi,
    required this.dropMonth,
    required this.totalPmiCost,
    required this.fmt,
    required this.fmtWhole,
  });

  @override
  Widget build(BuildContext context) {
    final yearsMonths = dropMonth != null
        ? '${dropMonth! ~/ 12}${isEs ? ' años' : ' yrs'} ${dropMonth! % 12}${isEs ? ' meses' : ' mo'}'
        : (isEs ? 'N/A' : 'N/A');

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Row(
              label: isEs ? 'Relación LTV' : 'LTV Ratio',
              value: '${ltv.toStringAsFixed(1)}%',
              color: ltv > 95
                  ? Colors.red
                  : ltv > 80
                      ? Colors.orange.shade700
                      : AppTheme.accentGood,
            ),
            _Row(
              label: isEs ? 'PMI mensual estimado (0.85%)' : 'Est. Monthly PMI (0.85%)',
              value: fmt.format(monthlyPmi),
              bold: true,
              color: Colors.orange.shade800,
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
                value: fmtWhole.format(totalPmiCost),
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
  final bool   bold;
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
                      color: Colors.grey.shade700, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color ?? (bold ? Colors.black87 : null),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
}

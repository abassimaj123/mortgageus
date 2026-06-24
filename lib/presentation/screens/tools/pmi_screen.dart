import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../providers/mortgage_providers.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../../main.dart'
    show paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../../core/services/pdf_export_service.dart';
import '../history/history_screen.dart' show HistoryScreen;

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

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('pmi');
    final input = ref.read(mortgageInputProvider);
    _homePriceCtrl.text = input.homePrice > 0 ? input.homePrice.toStringAsFixed(0) : '400000';
  }

  Future<void> _onInteraction() async {
    // Schedule auto-save
    final rawPrice = double.tryParse(_homePriceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0.0;
    final downAmt = rawPrice * _downPct / 100.0;
    final loan = (rawPrice - downAmt).clamp(0.0, double.infinity);
    final ltv = rawPrice > 0 ? (loan / rawPrice) * 100.0 : 0.0;
    final hasPmi = ltv > 80.0;
    if (rawPrice > 0 && hasPmi) {
      final input = ref.read(mortgageInputProvider);
      final monthlyPmi = MortgageCalculator.calcPmiMonthly(loanAmount: loan, homePrice: rawPrice, pmiAnnualRatePct: _pmiAnnualRate);
      final dropMonth = _monthsUntilPmiDrop(loanAmount: loan, homePrice: rawPrice, annualRatePct: input.annualRatePct, termYears: input.termYears);
      final totalPmiCost = dropMonth != null ? monthlyPmi * dropMonth : 0.0;
      final hash = ResultHasher.hashMixed({
        'loan_amount': _roundTo(loan, 5000),
        'home_value': _roundTo(rawPrice, 5000),
        'rate': _roundTo(input.annualRatePct, 0.25),
      });
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'pmi',
        inputHash: hash,
        l1: {
          'loan_amount': loan,
          'ltv': ltv,
          'monthly_pmi': monthlyPmi,
          'pmi_removal_date': dropMonth ?? 0,
        },
        l2: {
          'inputs': {
            'loan_amount': loan,
            'home_value': rawPrice,
            'rate': input.annualRatePct,
          },
          'results': {
            'ltv': ltv,
            'monthly_pmi': monthlyPmi,
            'annual_pmi': monthlyPmi * 12,
            'payoff_months': dropMonth ?? 0,
            'total_pmi_paid': totalPmiCost,
          },
        },
      );
      HistoryScreen.refreshNotifier.value++;
    }
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

  Future<void> _saveScenario(String? label) async {
    final rawPrice = double.tryParse(_homePriceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0.0;
    if (rawPrice <= 0) return;
    final downAmt = rawPrice * _downPct / 100.0;
    final loan = (rawPrice - downAmt).clamp(0.0, double.infinity);
    final ltv = rawPrice > 0 ? (loan / rawPrice) * 100.0 : 0.0;
    final input = ref.read(mortgageInputProvider);
    final monthlyPmi = MortgageCalculator.calcPmiMonthly(loanAmount: loan, homePrice: rawPrice, pmiAnnualRatePct: _pmiAnnualRate);
    final dropMonth = _monthsUntilPmiDrop(loanAmount: loan, homePrice: rawPrice, annualRatePct: input.annualRatePct, termYears: input.termYears);
    final totalPmiCost = dropMonth != null ? monthlyPmi * dropMonth : 0.0;
    final hash = ResultHasher.hashMixed({
      'loan_amount': _roundTo(loan, 5000),
      'home_value': _roundTo(rawPrice, 5000),
      'rate': _roundTo(input.annualRatePct, 0.25),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'pmi',
      inputHash: hash,
      l1: {
        'loan_amount': loan,
        'ltv': ltv,
        'monthly_pmi': monthlyPmi,
        'pmi_removal_date': dropMonth ?? 0,
      },
      l2: {
        'inputs': {
          'loan_amount': loan,
          'home_value': rawPrice,
          'rate': input.annualRatePct,
        },
        'results': {
          'ltv': ltv,
          'monthly_pmi': monthlyPmi,
          'annual_pmi': monthlyPmi * 12,
          'payoff_months': dropMonth ?? 0,
          'total_pmi_paid': totalPmiCost,
        },
      },
      label: label,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  Future<void> _exportPdf(bool isEs) async {
    final rawPrice = double.tryParse(
            _homePriceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
        0.0;
    if (rawPrice <= 0) return;
    final downAmt = rawPrice * _downPct / 100.0;
    final loan = (rawPrice - downAmt).clamp(0.0, double.infinity);
    final ltv = rawPrice > 0 ? (loan / rawPrice) * 100.0 : 0.0;
    final hasPmi = ltv > 80.0;
    if (!hasPmi) return;
    final input = ref.read(mortgageInputProvider);
    final monthlyPmi = MortgageCalculator.calcPmiMonthly(
        loanAmount: loan, homePrice: rawPrice, pmiAnnualRatePct: _pmiAnnualRate);
    final dropMonth = _monthsUntilPmiDrop(
        loanAmount: loan,
        homePrice: rawPrice,
        annualRatePct: input.annualRatePct,
        termYears: input.termYears);
    final totalPmiCost = dropMonth != null ? monthlyPmi * dropMonth : 0.0;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportPmiSimple(
        context,
        homePrice: rawPrice,
        downPct: _downPct,
        loanAmount: loan,
        ltv: ltv,
        monthlyPmi: monthlyPmi,
        dropMonth: dropMonth,
        totalPmiCost: totalPmiCost,
        isEs: isEs,
      );
    });
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'pmi');
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

        // Months until PMI auto-cancel — use rate/term from main calculator input
        final _input = ref.watch(mortgageInputProvider);
        final int? dropMonth = hasPmi
            ? _monthsUntilPmiDrop(
                loanAmount: loan,
                homePrice: rawPrice,
                annualRatePct: _input.annualRatePct,
                termYears: _input.termYears,
              )
            : null;

        final totalPmiCost = (dropMonth != null) ? monthlyPmi * dropMonth : 0.0;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Calculadora PMI' : 'PMI Calculator'),
          ),
          body: CalcwisePageEntrance(
              child: Column(children: [
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
                        AmountFormatter.ui(downAmt, 'USD'),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65),
                              fontSize: AppTextSize.sm)),
                      Text('25%',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65),
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
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65)),
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

                  const SizedBox(height: AppSpacing.md),

                  // ── Export PDF button ──────────────────────────────────────
                  if (hasPmi)
                    ValueListenableBuilder<bool>(
                      valueListenable: freemiumService.hasFullAccessNotifier,
                      builder: (context, hasFull, _) => SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _exportPdf(isEs);
                          },
                          icon: const Icon(Icons.picture_as_pdf_rounded,
                              size: 18),
                          label: Text(
                              isEs ? 'Exportar PDF' : 'Export PDF'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.mdPlus),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.mdPlus)),
                          ),
                        ),
                      ),
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
          ])),
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
                  ? CalcwiseSemanticColors.error(Theme.of(context).brightness)
                  : ltv > 80
                      ? CalcwiseSemanticColors.warnIcon
                      : AppTheme.accentGood,
            ),
            _Row(
              label: isEs
                  ? 'PMI mensual estimado (0.80%)'
                  : 'Est. Monthly PMI (0.80%)',
              value: AmountFormatter.ui(monthlyPmi, 'USD'),
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
                value: AmountFormatter.ui(totalPmiCost, 'USD'),
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

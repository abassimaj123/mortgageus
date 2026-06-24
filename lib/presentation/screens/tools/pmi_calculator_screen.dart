import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier, smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../widgets/save_scenario_button.dart';
import '../history/history_screen.dart' show HistoryScreen;

/// PMI Standalone Calculator
/// Monthly PMI = loan × annual_rate(by credit score & LTV) / 12.
/// Shows months until LTV reaches 80% (auto-cancel request) and 78% (mandatory).
class PmiCalculatorScreen extends ConsumerStatefulWidget {
  const PmiCalculatorScreen({super.key});

  @override
  ConsumerState<PmiCalculatorScreen> createState() =>
      _PmiCalculatorScreenState();
}

class _PmiCalculatorScreenState extends ConsumerState<PmiCalculatorScreen> {
  late final TextEditingController _homePriceCtrl;
  late final TextEditingController _rateCtrl;
  late double _downPct;
  int _creditScore = 720;
  bool _logged = false;

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('pmi_calculator');
    AnalyticsService.instance.maybeLogFirstCalculate();
    // Pre-fill from current calculator values
    final input = ref.read(mortgageInputProvider);
    final price = input.homePrice > 0 ? input.homePrice : 400000;
    final rate = input.annualRatePct > 0 ? input.annualRatePct : 7.0;
    _downPct = input.downPaymentPct.clamp(3.0, 19.9);
    _homePriceCtrl = TextEditingController(
        text: NumberFormat('#,##0').format(price.round()));
    _rateCtrl = TextEditingController(text: rate.toStringAsFixed(1));
  }

  static const int _term = 30;

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'pmi_calculator');
    _homePriceCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    // Schedule auto-save
    final price = _parse(_homePriceCtrl.text);
    final rate = double.tryParse(_rateCtrl.text) ?? 7.0;
    if (price > 0) {
      final down = price * _downPct / 100.0;
      final loan = (price - down).clamp(0.0, double.infinity);
      final ltv = price > 0 ? (loan / price) * 100.0 : 0.0;
      if (ltv > 80) {
        final annual = _pmiAnnualRatePct(_creditScore, ltv);
        final monthly = loan * annual / 100.0 / 12.0;
        final m80 = _monthsToLtv(loan: loan, price: price, targetLtv: 0.80, ratePct: rate);
        final m78 = _monthsToLtv(loan: loan, price: price, targetLtv: 0.78, ratePct: rate);
        final equityTarget = price * 0.20 - down;
        final hash = ResultHasher.hashMixed({
          'home_value': _roundTo(price, 5000),
          'loan_amount': _roundTo(loan, 5000),
          'pmi_rate': _roundTo(annual, 0.1),
        });
        smartHistoryService.scheduleAutoSave(
          appKey: 'mortgageus',
          screenId: 'pmi_calculator',
          inputHash: hash,
          l1: {
            'ltv': ltv,
            'monthly_pmi': monthly,
            'pmi_removal_equity': equityTarget,
            'months_to_removal': m80 ?? 0,
          },
          l2: {
            'inputs': {
              'home_value': price,
              'loan_amount': loan,
              'pmi_rate': annual,
            },
            'results': {
              'ltv': ltv,
              'monthly_pmi': monthly,
              'equity_target': equityTarget,
              'months_to_removal': m80 ?? 0,
            },
          },
        );
        HistoryScreen.refreshNotifier.value++;
      }
    }
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logPmiStandaloneCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  Future<void> _saveScenario(String? label) async {
    final price = _parse(_homePriceCtrl.text);
    if (price <= 0) return;
    final rate = double.tryParse(_rateCtrl.text) ?? 7.0;
    final down = price * _downPct / 100.0;
    final loan = (price - down).clamp(0.0, double.infinity);
    final ltv = price > 0 ? (loan / price) * 100.0 : 0.0;
    final annual = _pmiAnnualRatePct(_creditScore, ltv);
    final monthly = loan * annual / 100.0 / 12.0;
    final m80 = _monthsToLtv(loan: loan, price: price, targetLtv: 0.80, ratePct: rate);
    final equityTarget = price * 0.20 - down;
    final hash = ResultHasher.hashMixed({
      'home_value': _roundTo(price, 5000),
      'loan_amount': _roundTo(loan, 5000),
      'pmi_rate': _roundTo(annual, 0.1),
    });
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'pmi_calculator',
      inputHash: hash,
      l1: {
        'ltv': ltv,
        'monthly_pmi': monthly,
        'pmi_removal_equity': equityTarget,
        'months_to_removal': m80 ?? 0,
      },
      l2: {
        'inputs': {
          'home_value': price,
          'loan_amount': loan,
          'pmi_rate': annual,
        },
        'results': {
          'ltv': ltv,
          'monthly_pmi': monthly,
          'equity_target': equityTarget,
          'months_to_removal': m80 ?? 0,
        },
      },
      label: label,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  Future<void> _exportPdf(bool isEs) async {
    final price = _parse(_homePriceCtrl.text);
    if (price <= 0) return;
    final rate = double.tryParse(_rateCtrl.text) ?? 7.0;
    final down = price * _downPct / 100.0;
    final loan = (price - down).clamp(0.0, double.infinity);
    final ltv = price > 0 ? (loan / price) * 100.0 : 0.0;
    final annual = _pmiAnnualRatePct(_creditScore, ltv);
    final monthly = loan * annual / 100.0 / 12.0;
    final m80 = _monthsToLtv(loan: loan, price: price, targetLtv: 0.80, ratePct: rate);
    final m78 = _monthsToLtv(loan: loan, price: price, targetLtv: 0.78, ratePct: rate);
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportPmiCalculator(
        context,
        homePrice: price,
        downPct: _downPct,
        loanAmount: loan,
        ltv: ltv,
        creditScore: _creditScore,
        pmiAnnualRate: annual,
        monthlyPmi: monthly,
        monthsTo80: m80,
        monthsTo78: m78,
        rate: rate,
        isEs: isEs,
      );
    });
  }

  /// PMI annual rate by credit score and LTV tier (% per year).
  /// Rough industry-standard grid.
  double _pmiAnnualRatePct(int score, double ltv) {
    if (ltv <= 80) return 0.0;
    // LTV bands
    final tier = ltv > 95
        ? 0
        : ltv > 90
            ? 1
            : ltv > 85
                ? 2
                : 3;
    // Score bands
    final scoreBand = score >= 760
        ? 0
        : score >= 740
            ? 1
            : score >= 720
                ? 2
                : score >= 700
                    ? 3
                    : score >= 680
                        ? 4
                        : score >= 660
                            ? 5
                            : 6;
    // [ltvTier][scoreBand]
    const grid = <List<double>>[
      [0.55, 0.65, 0.78, 0.92, 1.10, 1.32, 1.55], // LTV > 95
      [0.41, 0.50, 0.62, 0.74, 0.88, 1.05, 1.25], // 90 < LTV ≤ 95
      [0.30, 0.36, 0.45, 0.55, 0.66, 0.80, 0.95], // 85 < LTV ≤ 90
      [0.19, 0.23, 0.28, 0.34, 0.42, 0.52, 0.64], // 80 < LTV ≤ 85
    ];
    return grid[tier][scoreBand];
  }

  int? _monthsToLtv({
    required double loan,
    required double price,
    required double targetLtv,
    required double ratePct,
  }) {
    if (price <= 0) return null;
    final target = price * targetLtv;
    if (loan <= target) return 0;
    final n = _term * 12;
    final r = ratePct / 100.0 / 12.0;
    final payment = MortgageCalculator.calcMonthlyPayment(
        loanAmount: loan, annualRatePct: ratePct, termYears: _term);
    double bal = loan;
    for (int m = 1; m <= n; m++) {
      final i = bal * r;
      final p = (payment - i).clamp(0.0, bal);
      bal -= p;
      if (bal <= target) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final price = _parse(_homePriceCtrl.text);
        final rate = double.tryParse(_rateCtrl.text) ?? 7.0;
        final down = price * _downPct / 100.0;
        final loan = (price - down).clamp(0.0, double.infinity);
        final ltv = price > 0 ? (loan / price) * 100.0 : 0.0;
        final annual = _pmiAnnualRatePct(_creditScore, ltv);
        final monthly = loan * annual / 100.0 / 12.0;
        final m80 = _monthsToLtv(
            loan: loan, price: price, targetLtv: 0.80, ratePct: rate);
        final m78 = _monthsToLtv(
            loan: loan, price: price, targetLtv: 0.78, ratePct: rate);



        String fmtMonths(int? m) {
          if (m == null) return isEs ? 'N/A' : 'N/A';
          if (m == 0) return isEs ? 'Ya alcanzado' : 'Already reached';
          return '${m ~/ 12}${isEs ? ' años' : ' yrs'} ${m % 12}${isEs ? ' meses' : ' mo'}';
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'PMI detallado' : 'PMI Detail'),
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
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText:
                              isEs ? 'Tasa de interés %' : 'Interest Rate %',
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
                              ? 'Pago inicial: ${_downPct.toStringAsFixed(1)}%'
                              : 'Down Payment: ${_downPct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd)),
                      Slider(
                        value: _downPct,
                        min: 3.0,
                        max: 25.0,
                        divisions: 220,
                        activeColor: AppTheme.primary,
                        onChanged: (v) => setState(() => _downPct = v),
                        onChangeEnd: (_) => _onInteraction(),
                      ),
                      Text(
                          isEs
                              ? 'Puntaje crediticio: $_creditScore'
                              : 'Credit Score: $_creditScore',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd)),
                      Slider(
                        value: _creditScore.toDouble(),
                        min: 620,
                        max: 820,
                        divisions: 20,
                        activeColor: AppTheme.primary,
                        onChanged: (v) =>
                            setState(() => _creditScore = v.round()),
                        onChangeEnd: (_) => _onInteraction(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AnimatedSwitcher(
                        duration: AppDuration.base,
                        child: price <= 0 || loan <= 0
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
                            : annual == 0
                                ? Container(
                                    key: const ValueKey('nopmi'),
                                    width: double.infinity,
                                    padding:
                                        const EdgeInsets.all(AppSpacing.lg),
                                    decoration: BoxDecoration(
                                      color: CalcwiseSemanticColors.successBg,
                                      border: Border.all(
                                          color: CalcwiseSemanticColors
                                              .successBorder),
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.lg),
                                    ),
                                    child: Row(children: [
                                      Icon(Icons.check_circle_outline,
                                          color: CalcwiseSemanticColors
                                              .successDeep,
                                          size: 24),
                                      const SizedBox(width: AppSpacing.md),
                                      Text(
                                          isEs
                                              ? 'No se requiere PMI'
                                              : 'No PMI Required',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: CalcwiseSemanticColors
                                                  .successDark,
                                              fontSize: AppTextSize.bodyLg)),
                                    ]),
                                  )
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
                                      padding:
                                          const EdgeInsets.all(AppSpacing.lg),
                                      child: Column(children: [
                                        _Row(
                                            label: isEs
                                                ? 'Relación LTV'
                                                : 'LTV Ratio',
                                            value:
                                                '${ltv.toStringAsFixed(1)}%'),
                                        _Row(
                                            label: isEs
                                                ? 'Tasa anual PMI'
                                                : 'PMI Annual Rate',
                                            value:
                                                '${annual.toStringAsFixed(2)}%'),
                                        _Row(
                                            label: isEs
                                                ? 'PMI mensual'
                                                : 'Monthly PMI',
                                            value: AmountFormatter.ui(monthly, 'USD'),
                                            bold: true,
                                            color: CalcwiseSemanticColors.alert(
                                                Theme.of(context).brightness)),
                                        const Divider(height: 24),
                                        _Row(
                                            label: isEs
                                                ? 'Cancelación voluntaria (LTV 80%)'
                                                : 'Cancel-on-request (LTV 80%)',
                                            value: fmtMonths(m80)),
                                        _Row(
                                            label: isEs
                                                ? 'Cancelación automática (LTV 78%)'
                                                : 'Auto-cancel (LTV 78%)',
                                            value: fmtMonths(m78),
                                            bold: true),
                                      ]),
                                    ),
                                  ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (price > 0) SaveScenarioButton(onSave: _saveScenario, labelEn: 'Save PMI Result', labelEs: 'Guardar resultado PMI'),
                      if (price > 0 && annual > 0) ...[
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
                                    ? 'La tasa de PMI varía según puntaje crediticio y LTV. Puedes solicitar cancelación al alcanzar 80% LTV; es obligatoria a 78%.'
                                    : 'PMI rate depends on credit score and LTV. You may request cancellation at 80% LTV; cancellation is mandatory at 78%.',
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

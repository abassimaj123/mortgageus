import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../domain/models/affordability_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/services/analytics_service.dart';
import '../../providers/mortgage_providers.dart';
import '../../../main.dart'
    show
        adService,
        paywallSession,
        isSpanishNotifier,
        preFillNotifier,
        tabSwitchNotifier,
        smartHistoryService;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;
import '../../widgets/save_scenario_button.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../../core/services/pdf_export_service.dart';

class AffordabilityScreen extends ConsumerStatefulWidget {
  const AffordabilityScreen({super.key});
  @override
  ConsumerState<AffordabilityScreen> createState() =>
      _AffordabilityScreenState();
}

class _AffordabilityScreenState extends ConsumerState<AffordabilityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _incomeCtrl = TextEditingController(text: '100000');
  final _debtsCtrl = TextEditingController(text: '500');
  final _downCtrl = TextEditingController(text: '60000');
  final _rateCtrl = TextEditingController(text: '6.8');
  final _taxCtrl = TextEditingController(text: '1.1');
  final _insuranceCtrl = TextEditingController(text: '1750');
  final _hoaCtrl = TextEditingController(text: '0');

  bool _advancedExpanded = false;
  int _termYears = 30;
  String? _incomeError;
  AffordabilityResult? _result;

  double _roundTo(double v, double step) => (v / step).round() * step;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('affordability');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Sync rate from main calculator provider, then auto-calculate
      final rate = ref.read(mortgageInputProvider).annualRatePct;
      _rateCtrl.text = rate.toStringAsFixed(2);
      if (mounted) await _calculate();
    });
  }

  @override
  void dispose() {
    smartHistoryService.cancelPendingSave('mortgageus', 'affordability');
    _incomeCtrl.dispose();
    _debtsCtrl.dispose();
    _downCtrl.dispose();
    _rateCtrl.dispose();
    _taxCtrl.dispose();
    _insuranceCtrl.dispose();
    _hoaCtrl.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final income = double.tryParse(_incomeCtrl.text.replaceAll(',', '')) ?? 0;
    final debts = double.tryParse(_debtsCtrl.text.replaceAll(',', '')) ?? 0;
    final down = double.tryParse(_downCtrl.text.replaceAll(',', '')) ?? 0;
    final rate = double.tryParse(_rateCtrl.text) ??
        MortgageConstants.defaultInterestRate;
    final tax = double.tryParse(_taxCtrl.text) ?? 1.1;
    final ins =
        double.tryParse(_insuranceCtrl.text.replaceAll(',', '')) ?? 1750;
    final hoa = double.tryParse(_hoaCtrl.text.replaceAll(',', '')) ?? 0;

    if (income <= 0) {
      setState(() => _incomeError = isSpanishNotifier.value
          ? 'Ingresa un ingreso anual válido'
          : 'Enter a valid annual income');
      return;
    }
    setState(() => _incomeError = null);

    setState(() {
      try {
        _result = MortgageCalculator.calcAffordability(
          annualIncome: income,
          monthlyDebts: debts,
          downPayment: down,
          annualRatePct: rate,
          termYears: _termYears,
          propertyTaxRatePct: tax,
          homeInsuranceAnnual: ins,
          hoaMonthly: hoa,
        );
      } catch (_) {
        _result = null;
      }
    });
    adService.onAction();
    AnalyticsService.instance.logAffordabilityCalculated();

    // SmartHistory auto-save
    final r2 = _result;
    if (r2 != null) {
      final maxHomePrice = r2.maxHomePriceStandard > 0 ? r2.maxHomePriceStandard : r2.maxHomePriceConservative;
      final hash = ResultHasher.hashMixed({
        'income': _roundTo(income, 5000),
        'debts': _roundTo(debts, 100),
        'rate': _roundTo(rate, 0.25),
        'term': _termYears,
      });
      final downPct = maxHomePrice > 0 ? (down / maxHomePrice * 100) : 0.0;
      smartHistoryService.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'affordability',
        inputHash: hash,
        l1: {
          'income': income,
          'max_home_price': maxHomePrice,
          'max_monthly': r2.totalMonthly,
          'down_pct': downPct,
        },
        l2: {
          'inputs': {
            'annual_income': income,
            'monthly_debts': debts,
            'down_payment': down,
            'rate': rate,
            'term_years': _termYears,
          },
          'results': {
            'max_loan': maxHomePrice - down,
            'max_home_price': maxHomePrice,
            'max_monthly': r2.totalMonthly,
            'dti': r2.monthlyPI,
          },
        },
      );
    }
    if (mounted) {
      final trigger = await paywallSession.recordAction();
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }
  }

  Future<void> _saveScenario(String? label) async {
    final r = _result;
    if (r == null) return;
    final income = double.tryParse(_incomeCtrl.text.replaceAll(',', '')) ?? 0;
    final debts = double.tryParse(_debtsCtrl.text.replaceAll(',', '')) ?? 0;
    final down = double.tryParse(_downCtrl.text.replaceAll(',', '')) ?? 0;
    final rate = double.tryParse(_rateCtrl.text) ?? MortgageConstants.defaultInterestRate;
    final maxHomePrice = r.maxHomePriceStandard > 0 ? r.maxHomePriceStandard : r.maxHomePriceConservative;
    final hash = ResultHasher.hashMixed({
      'income': _roundTo(income, 5000),
      'debts': _roundTo(debts, 100),
      'rate': _roundTo(rate, 0.25),
      'term': _termYears,
    });
    final downPct = maxHomePrice > 0 ? (down / maxHomePrice * 100) : 0.0;
    await smartHistoryService.saveScenario(
      appKey: 'mortgageus',
      screenId: 'affordability',
      inputHash: hash,
      l1: {
        'income': income,
        'max_home_price': maxHomePrice,
        'max_monthly': r.totalMonthly,
        'down_pct': downPct,
      },
      l2: {
        'inputs': {
          'annual_income': income,
          'monthly_debts': debts,
          'down_payment': down,
          'rate': rate,
          'term_years': _termYears,
        },
        'results': {
          'max_loan': maxHomePrice - down,
          'max_home_price': maxHomePrice,
          'max_monthly': r.totalMonthly,
          'dti': r.monthlyPI,
        },
      },
      label: freemiumService.hasFullAccess ? label : null,
    );
    AnalyticsService.instance.logHistorySaved();
  }

  Future<void> _exportPdf(bool isEs) async {
    final r = _result;
    if (r == null) return;
    final income = double.tryParse(_incomeCtrl.text.replaceAll(',', '')) ?? 0;
    final debts = double.tryParse(_debtsCtrl.text.replaceAll(',', '')) ?? 0;
    final down = double.tryParse(_downCtrl.text.replaceAll(',', '')) ?? 0;
    final rate = double.tryParse(_rateCtrl.text) ?? MortgageConstants.defaultInterestRate;
    await PdfExportService.showUnlockOrPay(context, () async {
      await PdfExportService.exportAffordability(
        context,
        annualIncome: income,
        monthlyDebts: debts,
        downPayment: down,
        annualRatePct: rate,
        termYears: _termYears,
        result: r,
        isEs: isEs,
      );
    });
  }

  void _useInCalculator() {
    final r = _result;
    if (r == null) return;
    // Use standard price (43% DTI), fall back to conservative
    final homePrice = r.maxHomePriceStandard > 0
        ? r.maxHomePriceStandard
        : r.maxHomePriceConservative;
    final rate = double.tryParse(_rateCtrl.text) ??
        MortgageConstants.defaultInterestRate;

    preFillNotifier.value = {
      'homePrice': homePrice,
      'downPayment': r.inputDownPayment,
      'rate': rate,
      'termYears': _termYears.toDouble(),
    };
    tabSwitchNotifier.value = 0; // switch to Calculator tab
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: CalcwisePageEntrance(child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Income + debts + down
                        _field(s.grossIncome, _incomeCtrl,
                            currency: true,
                            prefix: '\$',
                            errorText: _incomeError,
                            required: true),
                        const SizedBox(height: AppSpacing.md),
                        _field(s.monthlyDebts, _debtsCtrl,
                            currency: true, prefix: '\$'),
                        const SizedBox(height: AppSpacing.md),
                        _field(s.availDown, _downCtrl,
                            currency: true, prefix: '\$', required: true),
                        const SizedBox(height: AppSpacing.md),
                        // Rate + term
                        _field(s.interestRate, _rateCtrl,
                            suffix: '%', required: true),
                        const SizedBox(height: AppSpacing.md),
                        _TermRow(
                          selected: _termYears,
                          onChanged: (y) => setState(() => _termYears = y),
                          s: s,
                        ),
                        // Advanced toggle
                        const SizedBox(height: AppSpacing.xs),
                        InkWell(
                          onTap: () => setState(
                              () => _advancedExpanded = !_advancedExpanded),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm),
                            child: Row(children: [
                              Icon(
                                _advancedExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(s.advancedOptions,
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                        if (_advancedExpanded) ...[
                          _field(s.propertyTaxRate, _taxCtrl, suffix: '%'),
                          const SizedBox(height: AppSpacing.md),
                          _field(s.homeInsurance, _insuranceCtrl,
                              currency: true, prefix: '\$', suffix: '/yr'),
                          const SizedBox(height: AppSpacing.md),
                          _field(s.hoaFees, _hoaCtrl,
                              currency: true, prefix: '\$', suffix: '/mo'),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        InkWell(
                          onTap: _calculate,
                          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.mdPlus),
                            ),
                            alignment: Alignment.center,
                            child: Text(s.affordTitle,
                                style: TextStyle(
                                    fontSize: AppTextSize.bodyLg,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        // Results
                        if (r != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _ResultCard(
                              r: r, s: s, isEs: isEs),
                          const SizedBox(height: AppSpacing.md),
                          SaveScenarioButton(
                            onSave: _saveScenario,
                            labelEn: 'Save Affordability',
                            labelEs: 'Guardar asequibilidad',
                          ),
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
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: InkWell(
                              onTap: _useInCalculator,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              child: Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.all(AppSpacing.mdPlus),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentGood,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.calculate_rounded,
                                          color: Theme.of(context).colorScheme.onPrimary, size: 18),
                                      const SizedBox(width: AppSpacing.sm),
                                      Text(s.affordUseCalc,
                                          style: TextStyle(
                                              color: Theme.of(context).colorScheme.onPrimary,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: AppSpacing.xxl),
                          Center(
                            child: Text(s.affordEnterIncome,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppTheme.labelGray,
                                    fontSize: AppTextSize.md)),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.listBottomInset),
                      ]),
                ), // Form closes
              ),
            ),
          )),
        );
      },
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix,
      String? suffix,
      bool currency = false,
      String? errorText,
      bool required = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: currency ? [CurrencyInputFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        errorText: errorText,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
      ),
      validator: (v) {
        final raw = (v ?? '').trim();
        final es = isSpanishNotifier.value;
        if (raw.isEmpty) return required ? (es ? 'Requerido' : 'Required') : null;
        final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
        if (cleaned.isEmpty) return es ? 'Inválido' : 'Invalid';
        final n = double.tryParse(cleaned);
        if (n == null) return es ? 'Inválido' : 'Invalid';
        if (n < 0) return es ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
        return null;
      },
    );
  }
}

// ── Term row ──────────────────────────────────────────────────────────────────

class _TermRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final AppStrings s;
  const _TermRow(
      {required this.selected, required this.onChanged, required this.s});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.loanTerm, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Row(
              children: MortgageConstants.termPresets.map((t) {
            final sel = selected == t;
            return Expanded(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text('${t}yr'),
                selected: sel,
                selectedColor: AppTheme.primary,
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: sel ? Colors.white : null,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => onChanged(t),
              ),
            ));
          }).toList()),
        ],
      );
}

// ── Result card ───────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final AffordabilityResult r;
  final AppStrings s;
  final bool isEs;
  const _ResultCard({
    required this.r,
    required this.s,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Max home price highlights
      Row(children: [
        Expanded(
            child: _PriceCard(
          label: s.affordConservative,
          price: r.maxHomePriceConservative,
          color: AppTheme.accentGood,
        )),
        const SizedBox(width: AppSpacing.md),
        Expanded(
            child: _PriceCard(
          label: s.affordStandard,
          price: r.maxHomePriceStandard > 0
              ? r.maxHomePriceStandard
              : r.maxHomePriceConservative,
          color: AppTheme.primary,
        )),
      ]),
      const SizedBox(height: AppSpacing.lg),
      // Monthly breakdown
      Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(s.affordBreakdown,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyMd)),
            ),
            const Divider(height: 20),
            _Row('${s.principal} & ${s.interest}', AmountFormatter.ui(r.monthlyPI, 'USD')),
            _Row(s.propertyTax, AmountFormatter.ui(r.monthlyTax, 'USD')),
            _Row(s.homeInsurance, AmountFormatter.ui(r.monthlyInsurance, 'USD')),
            if (r.monthlyPMI > 0)
              _Row(s.pmi, AmountFormatter.ui(r.monthlyPMI, 'USD'),
                  color: CalcwiseSemanticColors.warnIcon),
            if (r.monthlyHOA > 0) _Row(s.hoa, AmountFormatter.ui(r.monthlyHOA, 'USD')),
            const Divider(height: 20),
            _Row(s.totalPITI, AmountFormatter.ui(r.totalMonthly, 'USD'), bold: true),
          ]),
        ),
      ),
    ]);
  }
}

class _PriceCard extends StatelessWidget {
  final String label;
  final double price;
  final Color color;
  const _PriceCard({
    required this.label,
    required this.price,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontSize: AppTextSize.xs,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Text(AmountFormatter.ui(price, 'USD'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.subtitle,
              )),
        ]),
      );
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const _Row(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Flexible(
            child: Text(label,
                style: TextStyle(
                    color: color ?? AppTheme.labelGray,
                    fontSize: AppTextSize.md)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: color ?? (bold ? AppTheme.primary : null),
                fontSize: AppTextSize.md,
              )),
        ]),
      );
}

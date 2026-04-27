import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../domain/models/affordability_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/ads/ad_service.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/freemium/paywall_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../providers/mortgage_providers.dart';
import '../../../main.dart' show isSpanishNotifier, preFillNotifier, tabSwitchNotifier;
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';

class AffordabilityScreen extends ConsumerStatefulWidget {
  const AffordabilityScreen({super.key});
  @override
  ConsumerState<AffordabilityScreen> createState() => _AffordabilityScreenState();
}

class _AffordabilityScreenState extends ConsumerState<AffordabilityScreen> {
  final _incomeCtrl   = TextEditingController(text: '100000');
  final _debtsCtrl    = TextEditingController(text: '500');
  final _downCtrl     = TextEditingController(text: '60000');
  final _rateCtrl     = TextEditingController();
  final _taxCtrl      = TextEditingController(text: '1.1');
  final _insuranceCtrl = TextEditingController(text: '1750');
  final _hoaCtrl      = TextEditingController(text: '0');

  bool    _advancedExpanded = false;
  int     _termYears        = 30;
  String? _incomeError;
  AffordabilityResult? _result;

  final _fmt  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rate = ref.read(mortgageInputProvider).annualRatePct;
      _rateCtrl.text = rate.toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _incomeCtrl.dispose();
    _debtsCtrl.dispose();
    _downCtrl.dispose();
    _rateCtrl.dispose();
    _taxCtrl.dispose();
    _insuranceCtrl.dispose();
    _hoaCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final income   = double.tryParse(_incomeCtrl.text.replaceAll(',', '')) ?? 0;
    final debts    = double.tryParse(_debtsCtrl.text.replaceAll(',', ''))  ?? 0;
    final down     = double.tryParse(_downCtrl.text.replaceAll(',', ''))   ?? 0;
    final rate     = double.tryParse(_rateCtrl.text)  ?? MortgageConstants.defaultInterestRate;
    final tax      = double.tryParse(_taxCtrl.text)   ?? 1.1;
    final ins      = double.tryParse(_insuranceCtrl.text.replaceAll(',', '')) ?? 1750;
    final hoa      = double.tryParse(_hoaCtrl.text.replaceAll(',', ''))   ?? 0;

    if (income <= 0) {
      setState(() => _incomeError = 'Enter a valid annual income');
      return;
    }
    setState(() => _incomeError = null);

    setState(() {
      try {
        _result = MortgageCalculator.calcAffordability(
          annualIncome:        income,
          monthlyDebts:        debts,
          downPayment:         down,
          annualRatePct:       rate,
          termYears:           _termYears,
          propertyTaxRatePct:  tax,
          homeInsuranceAnnual: ins,
          hoaMonthly:          hoa,
        );
      } catch (_) {
        _result = null;
      }
    });
    AdService.instance.onAction();
    AnalyticsService.instance.logAffordabilityCalculated();
    if (mounted) {
      final trigger = paywallService.recordAction();
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }
  }

  void _useInCalculator() {
    final r = _result;
    if (r == null) return;
    // Use standard price (43% DTI), fall back to conservative
    final homePrice = r.maxHomePriceStandard > 0
        ? r.maxHomePriceStandard
        : r.maxHomePriceConservative;
    final rate = double.tryParse(_rateCtrl.text) ?? MortgageConstants.defaultInterestRate;

    preFillNotifier.value = {
      'homePrice':  homePrice,
      'downPayment': r.inputDownPayment,
      'rate':        rate,
      'termYears':   _termYears.toDouble(),
    };
    tabSwitchNotifier.value = 0; // switch to Calculator tab
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          body: Column(children: [
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Income + debts + down
                _field(s.grossIncome,  _incomeCtrl, currency: true, prefix: '\$', errorText: _incomeError),
                const SizedBox(height: 12),
                _field(s.monthlyDebts, _debtsCtrl,  currency: true, prefix: '\$'),
                const SizedBox(height: 12),
                _field(s.availDown,    _downCtrl,   currency: true, prefix: '\$'),
                const SizedBox(height: 12),
                // Rate + term
                _field(s.interestRate, _rateCtrl, suffix: '%'),
                const SizedBox(height: 12),
                _TermRow(
                  selected: _termYears,
                  onChanged: (y) => setState(() => _termYears = y),
                  s: s,
                ),
                // Advanced toggle
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(
                        _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(s.advancedOptions,
                        style: const TextStyle(
                          color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                if (_advancedExpanded) ...[
                  _field(s.propertyTaxRate, _taxCtrl,      suffix: '%'),
                  const SizedBox(height: 12),
                  _field(s.homeInsurance,   _insuranceCtrl, currency: true, prefix: '\$', suffix: '/yr'),
                  const SizedBox(height: 12),
                  _field(s.hoaFees,         _hoaCtrl,       currency: true, prefix: '\$', suffix: '/mo'),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _calculate,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16)),
                    child: Text(s.affordTitle,
                      style: const TextStyle(fontSize: 16)),
                  ),
                ),
                // Results
                if (r != null) ...[
                  const SizedBox(height: 20),
                  _ResultCard(r: r, fmt: _fmt, fmtK: _fmtK, s: s, isEs: isEs),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _useInCalculator,
                      icon: const Icon(Icons.calculate_outlined),
                      label: Text(s.affordUseCalc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentGood,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Text(s.affordEnterIncome,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 80),
              ]),
            )),
            const AdFooter(),
          ]),
        );
      },
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? prefix, String? suffix, bool currency = false, String? errorText}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: currency ? [CurrencyInputFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        errorText: errorText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ── Term row ──────────────────────────────────────────────────────────────────

class _TermRow extends StatelessWidget {
  final int              selected;
  final ValueChanged<int> onChanged;
  final dynamic          s;
  const _TermRow({required this.selected, required this.onChanged, required this.s});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.loanTerm, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: MortgageConstants.termPresets.map((t) {
        final sel = selected == t;
        return Expanded(child: Padding(
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
  final NumberFormat        fmt;
  final NumberFormat        fmtK;
  final dynamic             s;
  final bool                isEs;
  const _ResultCard({
    required this.r, required this.fmt, required this.fmtK,
    required this.s, required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Max home price highlights
      Row(children: [
        Expanded(child: _PriceCard(
          label: s.affordConservative,
          price: r.maxHomePriceConservative,
          fmt: fmt,
          color: AppTheme.accentGood,
        )),
        const SizedBox(width: 12),
        Expanded(child: _PriceCard(
          label: s.affordStandard,
          price: r.maxHomePriceStandard > 0 ? r.maxHomePriceStandard : r.maxHomePriceConservative,
          fmt: fmt,
          color: AppTheme.primary,
        )),
      ]),
      const SizedBox(height: 16),
      // Monthly breakdown
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(s.affordBreakdown,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const Divider(height: 20),
            _Row('${s.principal} & ${s.interest}', fmt.format(r.monthlyPI)),
            _Row(s.propertyTax,   fmt.format(r.monthlyTax)),
            _Row(s.homeInsurance, fmt.format(r.monthlyInsurance)),
            if (r.monthlyPMI > 0) _Row(s.pmi, fmt.format(r.monthlyPMI), color: Colors.orange),
            if (r.monthlyHOA > 0) _Row(s.hoa, fmt.format(r.monthlyHOA)),
            const Divider(height: 20),
            _Row(s.totalPITI, fmt.format(r.totalMonthly), bold: true),
          ]),
        ),
      ),
    ]);
  }
}

class _PriceCard extends StatelessWidget {
  final String       label;
  final double       price;
  final NumberFormat fmt;
  final Color        color;
  const _PriceCard({
    required this.label, required this.price,
    required this.fmt, required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Column(children: [
      Text(label,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(fmt.format(price),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        )),
    ]),
  );
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool   bold;
  final Color? color;
  const _Row(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: color ?? Colors.grey.shade700, fontSize: 13)),
      Text(value, style: TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        color: color ?? (bold ? AppTheme.primary : null),
        fontSize: 13,
      )),
    ]),
  );
}

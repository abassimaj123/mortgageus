import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/services/review_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../../domain/models/loan_type.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../providers/mortgage_providers.dart';
import '../../../core/ads/ad_footer.dart';
import '../history/history_screen.dart' show HistoryScreen;
import '../../../core/services/analytics_service.dart';
import '../../../main.dart' show isSpanishNotifier, preFillNotifier;
import '../../../core/freemium/paywall_service.dart';
import '../../widgets/paywall_soft.dart';
import '../../widgets/paywall_hard.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../../widgets/info_tooltip.dart';

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});
  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  final _homePriceCtrl = TextEditingController(text: '400000');
  final _downPayCtrl   = TextEditingController(text: '20');
  final _rateCtrl      = TextEditingController(text: '6.5');
  final _taxCtrl       = TextEditingController(text: '1.1');
  final _insuranceCtrl = TextEditingController(text: '1750');
  final _hoaCtrl       = TextEditingController(text: '0');
  final _incomeCtrl    = TextEditingController();
  double _monthlyIncome = 0.0;
  bool _advancedExpanded = false;
  String? _homePriceError;

  final _fmt  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

  @override
  void initState() {
    super.initState();
    // Push controller defaults to provider on first frame so all tabs are in sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = ref.read(mortgageInputProvider.notifier);
      n.updateHomePrice(400000);
      n.updateDownPaymentPct(20);
      n.updateRate(6.5);
      n.updatePropertyTaxRate(1.1);
      n.updateHomeInsurance(1750);
      n.updateHoa(0);
    });
    preFillNotifier.addListener(_onPreFill);
  }

  void _onPreFill() {
    final data = preFillNotifier.value;
    if (data == null) return;
    preFillNotifier.value = null; // consume immediately to avoid loops

    final n = ref.read(mortgageInputProvider.notifier);

    if (data.containsKey('homePrice')) {
      final hp = data['homePrice']!;
      _homePriceCtrl.text = hp.toStringAsFixed(0);
      n.updateHomePrice(hp);
    }
    if (data.containsKey('downPayment')) {
      final dp = data['downPayment']!;
      final hp = data['homePrice'] ?? ref.read(mortgageInputProvider).homePrice;
      final pct = hp > 0 ? (dp / hp) * 100 : 20.0;
      _downPayCtrl.text = pct.toStringAsFixed(1);
      n.updateDownPaymentPct(pct);
    }
    if (data.containsKey('rate')) {
      final r = data['rate']!;
      _rateCtrl.text = r.toStringAsFixed(2);
      n.updateRate(r);
    }
    if (data.containsKey('termYears')) {
      n.updateTerm(data['termYears']!.toInt());
    }
  }

  @override
  void dispose() {
    preFillNotifier.removeListener(_onPreFill);
    _homePriceCtrl.dispose();
    _downPayCtrl.dispose();
    _rateCtrl.dispose();
    _taxCtrl.dispose();
    _insuranceCtrl.dispose();
    _hoaCtrl.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveToHistory({bool showFeedback = false}) async {
    final result = ref.read(mortgageResultProvider);
    if (result == null || result.loanAmount <= 0) return;

    final inputState = ref.read(mortgageInputProvider);
    final label = '${inputState.homePrice ~/ 1000}K · ${inputState.annualRatePct.toStringAsFixed(2)}% · ${inputState.termYears}yr';
    await DatabaseHelper.instance.insertHistory({
      'home_price':      inputState.homePrice,
      'down_percent':    inputState.downPaymentPct,
      'annual_rate':     inputState.annualRatePct,
      'monthly_payment': result.monthly.pitiPayment,
      'total_interest':  result.totalInterest,
      'loan_amount':     result.loanAmount,
      'loan_type':       inputState.loanType.label,
      'term_years':      inputState.termYears,
      'tax_rate':        inputState.propertyTaxRatePct,
      'insurance':       inputState.homeInsuranceAnnual,
      'hoa':             inputState.hoaMonthly,
      'created_at':      DateTime.now().toIso8601String(),
      'label':           label,
    });

    // Refresh history tab immediately
    HistoryScreen.refreshNotifier.value++;
    ReviewService.instance.requestAfterSave();
    AnalyticsService.instance.logHistorySaved();
    if (mounted) {
      final trigger = paywallService.recordAction();
      if (trigger == PaywallTrigger.soft) PaywallSoft.show(context);
      if (trigger == PaywallTrigger.hard) PaywallHard.show(context);
    }

    if (!mounted) return;
    final isEs = isSpanishNotifier.value;

    // Free users: FIFO cap — remove oldest, show informative snackbar
    if (!freemiumService.isPremium) {
      final count = await DatabaseHelper.instance.countHistory();
      if (count > freemiumService.historyLimit) {
        await DatabaseHelper.instance.deleteOldestHistory();
        HistoryScreen.refreshNotifier.value++;
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isEs
                ? 'Guardado · entrada más antigua reemplazada · ${freemiumService.historyLimit}/${freemiumService.historyLimit} slots'
                : 'Saved · oldest entry replaced · ${freemiumService.historyLimit}/${freemiumService.historyLimit} free slots'),
            action: SnackBarAction(
              label: isEs ? 'Ilimitado' : 'Unlock unlimited',
              onPressed: () => IAPService.instance.buy(),
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
    }

    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isEs ? 'Cálculo guardado' : 'Calculation saved'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final result     = ref.watch(mortgageResultProvider);
    final inputState = ref.watch(mortgageInputProvider);
    final notifier   = ref.read(mortgageInputProvider.notifier);

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    // ── Hero card ───────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: _HeroCard(result: result, s: s),
                    ),
                    // ── Inputs ──────────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      // Home Price
                      _buildField(s.homePrice, _homePriceCtrl, prefix: '\$',
                        currency: true,
                        errorText: _homePriceError,
                        onChanged: (v) {
                          final hp = double.tryParse(v.replaceAll(',', '')) ?? 0;
                          notifier.updateHomePrice(hp);
                          setState(() {
                            _homePriceError = hp <= 0 ? (isEs ? 'Ingresa un precio válido' : 'Enter a valid home price') : null;
                          });
                        }),
                      const SizedBox(height: 12),
                      // Down Payment row
                      _DownPaymentRow(
                        ctrl: _downPayCtrl,
                        notifier: notifier,
                        inputState: inputState,
                        s: s,
                      ),
                      const SizedBox(height: 12),
                      // Interest Rate
                      _buildField(s.interestRate, _rateCtrl, suffix: '%',
                        onChanged: (v) => notifier.updateRate(double.tryParse(v.replaceAll(',', '.')) ?? 6.5)),
                      const SizedBox(height: 12),
                      // Term chips
                      _TermSelector(inputState: inputState, notifier: notifier, s: s),
                      const SizedBox(height: 12),
                      // Loan type chips
                      _LoanTypeSelector(inputState: inputState, notifier: notifier, s: s),
                      const SizedBox(height: 16),
                      // Advanced toggle
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
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              )),
                          ]),
                        ),
                      ),
                      if (_advancedExpanded) ...[
                        const SizedBox(height: 8),
                        _buildField(s.propertyTaxRate, _taxCtrl, suffix: '%',
                          onChanged: (v) =>
                            notifier.updatePropertyTaxRate(double.tryParse(v.replaceAll(',', '.')) ?? 1.1)),
                        const SizedBox(height: 12),
                        _buildField(s.homeInsurance, _insuranceCtrl,
                          prefix: '\$', suffix: '/yr',
                          onChanged: (v) =>
                            notifier.updateHomeInsurance(double.tryParse(v.replaceAll(',', '.')) ?? 1750)),
                        const SizedBox(height: 12),
                        _buildField(s.hoaFees, _hoaCtrl, prefix: '\$', suffix: '/mo',
                          onChanged: (v) => notifier.updateHoa(double.tryParse(v.replaceAll(',', '.')) ?? 0)),
                        const SizedBox(height: 12),
                        _buildField(
                          isEs
                              ? 'Ingreso Mensual Bruto (opcional)'
                              : 'Monthly Gross Income (optional)',
                          _incomeCtrl,
                          prefix: '\$',
                          onChanged: (v) => setState(() {
                            _monthlyIncome = double.tryParse(v.replaceAll(',', '')) ?? 0.0;
                          }),
                          currency: true,
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Breakdown card
                      if (result != null)
                        _BreakdownCard(result: result, fmt: _fmt, fmtK: _fmtK, s: s, isEs: isEs),
                      // ── Stress Test Banner ──────────────────────────────
                      if (result != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.accentWarn.withValues(alpha: 0.08),
                            border: Border.all(color: AppTheme.accentWarn.withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: AppTheme.accentWarn, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  isEs ? 'Prueba de Estrés (+2%)' : 'Stress Test (+2%)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accentWarn,
                                    fontSize: 14,
                                  ),
                                ),
                                InfoTooltip(
                                  title: isEs ? 'Prueba de Estrés' : 'Stress Test',
                                  body: isEs
                                      ? 'Su tasa de calificación es su tasa contractual + 2%. Los prestamistas usan esto para asegurarse de que pueda pagar si suben las tasas.'
                                      : 'Your qualifying rate is your contract rate + 2%. Lenders use this to ensure you can still afford payments if interest rates rise.',
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Text(
                                isEs
                                    ? 'Si el interés sube a ${result.stressTestRate.toStringAsFixed(2)}%, tu pago mensual sería: ${_fmt.format(result.stressTestMonthly)}'
                                    : 'If your rate rises to ${result.stressTestRate.toStringAsFixed(2)}%, your monthly P&I would be: ${_fmt.format(result.stressTestMonthly)}',
                                style: const TextStyle(
                                  color: AppTheme.accentWarn,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // ── Affordability badge ────────────────────────────
                      if (result != null && _monthlyIncome > 0) ...[
                        const SizedBox(height: 12),
                        _AffordabilityBadge(
                          pitiPayment: result.monthly.pitiPayment,
                          monthlyIncome: _monthlyIncome,
                          isEs: isEs,
                        ),
                      ],
                      if (result != null) ...[
                        const SizedBox(height: 12),
                        // Save button — always visible, triggers FIFO at limit
                        OutlinedButton.icon(
                          onPressed: () => _saveToHistory(showFeedback: true),
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(s.saveCalc),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            foregroundColor: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // PDF button — visible for all, locked for non-premium
                        ValueListenableBuilder<bool>(
                          valueListenable: freemiumService.isPremiumNotifier,
                          builder: (context, isPremium, _) {
                            return OutlinedButton.icon(
                              onPressed: isPremium
                                  ? () {
                                      PdfExportService.exportMortgage(context, inputState, result);
                                      AnalyticsService.instance.logPdfExported();
                                    }
                                  : () { PdfExportService.showUnlockOrPay(
                                        context,
                                        () async {
                                          PdfExportService.exportMortgage(context, inputState, result);
                                          await AnalyticsService.instance.logPdfExported();
                                        }); },
                              icon: Icon(isPremium
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.lock_outline),
                              label: Text(isPremium ? s.exportPdf : s.exportPdfPremium),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                foregroundColor: isPremium
                                    ? AppTheme.primary
                                    : AppTheme.secondary,
                                side: BorderSide(
                                  color: isPremium
                                      ? AppTheme.primary
                                      : AppTheme.secondary,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        // Share button — free users: PaywallSoft if session threshold reached
                        OutlinedButton.icon(
                          onPressed: () {
                            final isEs = isSpanishNotifier.value;
                            // PaywallSoft check for free users at threshold
                            if (!freemiumService.isPremium) {
                              final trigger = paywallService.recordAction();
                              if (trigger == PaywallTrigger.soft) {
                                PaywallSoft.show(context);
                                return;
                              }
                              if (trigger == PaywallTrigger.hard) {
                                PaywallHard.show(context);
                                return;
                              }
                            }
                            final fmt = NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 0);
                            final text = isEs
                                ? '🏠 Resumen hipotecario\n'
                                  'Precio: ${fmt.format(inputState.homePrice)}\n'
                                  'Inicial: ${inputState.downPaymentPct.toStringAsFixed(1)}% (${fmt.format(inputState.downPaymentDollar)})\n'
                                  'Tasa: ${inputState.annualRatePct.toStringAsFixed(2)}%\n'
                                  'Mensual: ${fmt.format(result.monthly.pitiPayment)}\n'
                                  'Interés total: ${fmt.format(result.totalInterest)}\n'
                                  '— Calculado con Mortgage Calculator US'
                                : '🏠 Mortgage Summary\n'
                                  'Price: ${fmt.format(inputState.homePrice)}\n'
                                  'Down: ${inputState.downPaymentPct.toStringAsFixed(1)}% (${fmt.format(inputState.downPaymentDollar)})\n'
                                  'Rate: ${inputState.annualRatePct.toStringAsFixed(2)}%\n'
                                  'Monthly: ${fmt.format(result.monthly.pitiPayment)}\n'
                                  'Total Interest: ${fmt.format(result.totalInterest)}\n'
                                  '— Calculated with Mortgage Calculator US';
                            Share.share(text);
                          },
                          icon: const Icon(Icons.share_outlined),
                          label: Text(isSpanishNotifier.value ? 'Compartir' : 'Share'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ],
                          const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const AdFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    String? suffix,
    bool currency = false,
    String? errorText,
    required Function(String) onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: currency
          ? [CurrencyInputFormatter()]
          : [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        errorText: errorText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onChanged: onChanged,
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final dynamic result;
  final dynamic s;
  const _HeroCard({this.result, required this.s});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.monthlyPI,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            result != null ? fmt.format(result!.monthly.piPayment) : '--',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          if (result != null) ...[
            Text(
              '${s.totalPITI}: ${fmt.format(result!.monthly.pitiPayment)}',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              _Badge(
                label: result!.isJumbo ? s.jumbo : s.conforming,
                color: result!.isJumbo ? AppTheme.accentWarn : AppTheme.accentGood,
              ),
              _Badge(
                label: 'LTV ${result!.currentLtv.toStringAsFixed(1)}%',
                color: result!.currentLtv < 80
                    ? AppTheme.accentGood
                    : result!.currentLtv < 95
                        ? AppTheme.accentWarn
                        : Colors.red,
              ),
              if (result!.hasPmi)
                _Badge(
                  label: result!.isUsda ? s.usdaFee : s.pmi,
                  color: result!.isUsda ? AppTheme.accentGood : Colors.orange,
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      )),
  );
}

// ── Term selector ─────────────────────────────────────────────────────────────

class _TermSelector extends ConsumerWidget {
  final MortgageInputState    inputState;
  final MortgageInputNotifier notifier;
  final dynamic               s;
  const _TermSelector({required this.inputState, required this.notifier, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.loanTerm, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: MortgageConstants.termPresets.map((term) {
            final selected = inputState.termYears == term;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  label: '$term year loan term, ${selected ? "selected" : "not selected"}',
                  child: ChoiceChip(
                    label: Text('${term}yr'),
                    selected: selected,
                    selectedColor: AppTheme.primary,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => notifier.updateTerm(term),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Loan type selector ────────────────────────────────────────────────────────

class _LoanTypeSelector extends ConsumerWidget {
  final MortgageInputState    inputState;
  final MortgageInputNotifier notifier;
  final dynamic               s;
  const _LoanTypeSelector({required this.inputState, required this.notifier, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.loanType, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: LoanType.values.map((type) {
            final selected = inputState.loanType == type;
            return Semantics(
              label: '${type.label} loan type, ${selected ? "selected" : "not selected"}',
              child: ChoiceChip(
                label: Text(type.label),
                selected: selected,
                selectedColor: AppTheme.primary,
                labelStyle: TextStyle(color: selected ? Colors.white : null),
                onSelected: (_) => notifier.updateLoanType(type),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Down payment row ──────────────────────────────────────────────────────────

class _DownPaymentRow extends ConsumerWidget {
  final TextEditingController ctrl;
  final MortgageInputState    inputState;
  final MortgageInputNotifier notifier;
  final dynamic               s;
  const _DownPaymentRow({
    required this.ctrl,
    required this.inputState,
    required this.notifier,
    required this.s,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: s.downPayment,
            suffixText: inputState.downPaymentAsDollar ? null : '%',
            prefixText: inputState.downPaymentAsDollar ? '\$' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (v) {
            if (inputState.downPaymentAsDollar) {
              final dollars = double.tryParse(v) ?? 0;
              final pct = inputState.homePrice > 0
                  ? (dollars / inputState.homePrice) * 100
                  : 0.0;
              notifier.updateDownPaymentPct(pct);
            } else {
              notifier.updateDownPaymentPct(double.tryParse(v) ?? 20);
            }
          },
        ),
      ),
      const SizedBox(width: 8),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _ModeBtn(
            label: '\$',
            selected: inputState.downPaymentAsDollar,
            onTap: () => notifier.toggleDownPaymentMode(true),
          ),
          _ModeBtn(
            label: '%',
            selected: !inputState.downPaymentAsDollar,
            onTap: () => notifier.toggleDownPaymentMode(false),
          ),
        ]),
      ),
    ]);
  }
}

// ── Affordability badge ───────────────────────────────────────────────────────

class _AffordabilityBadge extends StatelessWidget {
  final double pitiPayment;
  final double monthlyIncome;
  final bool   isEs;
  const _AffordabilityBadge({
    required this.pitiPayment,
    required this.monthlyIncome,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = pitiPayment / monthlyIncome;
    final pct   = (ratio * 100).toStringAsFixed(1);

    final Color badgeColor;
    final String badgeLabel;
    if (ratio < 0.28) {
      badgeColor = AppTheme.accentGood;
      badgeLabel = isEs ? 'Asequible' : 'Affordable';
    } else if (ratio < 0.36) {
      badgeColor = AppTheme.accentWarn;
      badgeLabel = isEs ? 'Al Límite' : 'At the Limit';
    } else {
      badgeColor = Colors.red;
      badgeLabel = isEs ? 'Supera el Límite' : 'Over Limit';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, color: badgeColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEs
                  ? 'Costo de vivienda: $pct% del ingreso'
                  : 'Housing cost: $pct% of income',
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          InfoTooltip(
            title: isEs ? 'Ratio de Costo de Vivienda' : 'Housing Cost Ratio',
            body: isEs
                ? 'Sus costos mensuales de vivienda (capital + interés + impuesto + seguro + HOA + PMI) como % de su ingreso mensual bruto. Los prestamistas generalmente permiten hasta 28-36%.'
                : 'Your monthly housing costs (P&I + property tax + insurance + HOA + PMI) as a % of gross monthly income. Lenders typically allow up to 28–36%.',
          ),
        ],
      ),
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final String      label;
  final bool        selected;
  final VoidCallback onTap;
  const _ModeBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : null,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.grey.shade600,
          fontWeight: FontWeight.bold,
        )),
    ),
  );
}

// ── Breakdown card ────────────────────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final dynamic result;
  final NumberFormat fmt;
  final NumberFormat fmtK;
  final dynamic s;
  final bool isEs;
  const _BreakdownCard({this.result, required this.fmt, required this.fmtK, required this.s, required this.isEs});

  @override
  Widget build(BuildContext context) {
    final m = result!.monthly;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _Row(s.principal,      fmt.format(m.principal)),
          _Row(s.interest,       fmt.format(m.interest)),
          _Row(s.propertyTax,    fmt.format(m.propertyTax)),
          _Row(s.homeInsurance,  fmt.format(m.homeInsurance)),
          if (m.hoa > 0) _Row(s.hoa, fmt.format(m.hoa)),
          if (m.pmi > 0) _Row(
            result!.isUsda
                ? s.usdaFeeLabel
                : '${s.pmiDropsAt} ${result!.pmiDropMonth ?? "?"}${s.mo})',
            fmt.format(m.pmi),
            color: result!.isUsda ? AppTheme.accentGood : Colors.orange,
            tooltip: result!.isUsda
                ? InfoTooltip(
                    title: isEs ? 'Cuota Anual USDA' : 'USDA Annual Fee',
                    body: isEs
                        ? 'Los préstamos USDA incluyen una cuota de garantía inicial del 1% (financiada) y una cuota anual del 0.35%. Nunca se cancela durante la vigencia del préstamo.'
                        : 'USDA loans include a 1% upfront guarantee fee (financed) and 0.35% annual fee. It never drops for the life of the loan.',
                  )
                : InfoTooltip(
                    title: isEs ? 'PMI — Seguro Hipotecario Privado' : 'PMI — Private Mortgage Insurance',
                    body: isEs
                        ? 'Requerido cuando el pago inicial es menor al 20%. Protege al prestamista, no a usted. Se cancela automáticamente cuando el saldo del préstamo llega al 78% del valor original.'
                        : 'Required when your down payment is less than 20%. Protects the lender, not you. Automatically cancels when your loan balance reaches 78% of the original home value.',
                  ),
          ),
          const Divider(height: 24),
          _Row(s.totalPITI, fmt.format(m.pitiPayment), bold: true),
          const SizedBox(height: 8),
          _Row(s.totalInterest, fmtK.format(result!.totalInterest)),
          _Row(s.totalCost,     fmtK.format(result!.totalCost)),
          _Row(s.payoffDate,
            '${result!.payoffDate.month}/${result!.payoffDate.year}'),
          _Row(
            isEs ? 'LTV' : 'LTV',
            '${result!.currentLtv.toStringAsFixed(1)}%',
            tooltip: InfoTooltip(
              title: isEs ? 'LTV — Préstamo a Valor' : 'LTV — Loan-to-Value',
              body: isEs
                  ? 'El monto del préstamo dividido por el precio de la casa. Por debajo del 80% LTV = no se requiere PMI. Un LTV más bajo generalmente significa mejores tasas.'
                  : 'Your loan amount divided by the home price. Below 80% LTV = no PMI required. Lower LTV typically means better interest rates.',
            ),
          ),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String   label, value;
  final bool     bold;
  final Color?   color;
  final Widget?  tooltip;
  const _Row(this.label, this.value, {this.bold = false, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: color ?? Colors.grey.shade700)),
            if (tooltip != null) tooltip!,
          ],
        ),
        Text(value, style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: color ?? (bold ? AppTheme.primary : null),
        )),
      ],
    ),
  );
}

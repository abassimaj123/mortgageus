import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/services/analytics_service.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;

/// FHA Loan Calculator
/// Min 3.5% down. Upfront MIP = 1.75% of loan (financed).
/// Annual MIP: LTV > 95% → 0.55%/yr ; LTV ≤ 95% → 0.50%/yr.
class FhaScreen extends ConsumerStatefulWidget {
  const FhaScreen({super.key});

  @override
  ConsumerState<FhaScreen> createState() => _FhaScreenState();
}

class _FhaScreenState extends ConsumerState<FhaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _homePriceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '300');
  final _insCtrl = TextEditingController(text: '120');
  double _downPct = 3.5;
  int _creditScore = 680;
  bool _logged = false;

  double _rate = 7.0;
  static const int _term = 30;

  @override
  void initState() {
    super.initState();
    final input = ref.read(mortgageInputProvider);
    _homePriceCtrl.text = input.homePrice.toStringAsFixed(0);
    _rate = input.annualRatePct;
  }

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
    AnalyticsService.instance.logFhaCalculated();
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
        final price = _parse(_homePriceCtrl.text);
        final down = price * _downPct / 100.0;
        final baseLoan = (price - down).clamp(0.0, double.infinity);
        final upfrontMip = baseLoan * 0.0175;
        final loan = baseLoan + upfrontMip; // financed
        final ltv = price > 0 ? (baseLoan / price) * 100.0 : 0.0;
        final annualMipRate = ltv > 95 ? 0.0055 : 0.0050;
        final monthlyMip = loan * annualMipRate / 12.0;
        final pAndI = loan > 0
            ? MortgageCalculator.calcMonthlyPayment(
                loanAmount: loan, annualRatePct: _rate, termYears: _term)
            : 0.0;
        final tax = _parse(_taxCtrl.text);
        final ins = _parse(_insCtrl.text);
        final total = pAndI + monthlyMip + tax + ins;


        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Préstamo FHA' : 'FHA Loan'),
          ),
          body: Column(children: [
            Expanded(
              child: CalcwisePageEntrance(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
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
                          validator: (v) {
                            final raw = (v ?? '').trim();
                            if (raw.isEmpty)
                              return isEs ? 'Requerido' : 'Required';
                            final cleaned =
                                raw.replaceAll(RegExp(r'[^0-9.]'), '');
                            final n = double.tryParse(cleaned);
                            if (n == null) return isEs ? 'Inválido' : 'Invalid';
                            if (n < 0)
                              return isEs ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
                            return null;
                          },
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
                            Text(AmountFormatter.ui(down, 'USD'),
                                style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Slider(
                          value: _downPct,
                          min: 3.5,
                          max: 30.0,
                          divisions: 265,
                          activeColor: AppTheme.primary,
                          onChanged: (v) => setState(() => _downPct = v),
                          onChangeEnd: (_) => _onInteraction(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                            isEs
                                ? 'Puntaje crediticio: $_creditScore'
                                : 'Credit Score: $_creditScore',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: AppTextSize.bodyMd)),
                        Slider(
                          value: _creditScore.toDouble(),
                          min: 580,
                          max: 820,
                          divisions: 24,
                          activeColor: AppTheme.primary,
                          onChanged: (v) =>
                              setState(() => _creditScore = v.round()),
                          onChangeEnd: (_) => _onInteraction(),
                        ),
                        const SizedBox(height: AppSpacing.md),
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
                              validator: (v) {
                                final raw = (v ?? '').trim();
                                if (raw.isEmpty) return null;
                                final cleaned =
                                    raw.replaceAll(RegExp(r'[^0-9.]'), '');
                                final n = double.tryParse(cleaned);
                                if (n == null)
                                  return isEs ? 'Inválido' : 'Invalid';
                                if (n < 0)
                                  return isEs ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
                                return null;
                              },
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
                              validator: (v) {
                                final raw = (v ?? '').trim();
                                if (raw.isEmpty) return null;
                                final cleaned =
                                    raw.replaceAll(RegExp(r'[^0-9.]'), '');
                                final n = double.tryParse(cleaned);
                                if (n == null)
                                  return isEs ? 'Inválido' : 'Invalid';
                                if (n < 0)
                                  return isEs ? 'Debe ser ≥ 0' : 'Must be ≥ 0';
                                return null;
                              },
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
                                    padding:
                                        const EdgeInsets.all(AppSpacing.lg),
                                    child: Column(children: [
                                      _Row(
                                          label: isEs
                                              ? 'Monto del préstamo'
                                              : 'Loan Amount',
                                          value: AmountFormatter.ui(loan, 'USD')),
                                      _Row(
                                          label: isEs
                                              ? 'MIP inicial (1.75%)'
                                              : 'Upfront MIP (1.75%)',
                                          value: AmountFormatter.ui(upfrontMip, 'USD')),
                                      _Row(
                                          label: isEs
                                              ? 'MIP mensual (${(annualMipRate * 100).toStringAsFixed(2)}%)'
                                              : 'Monthly MIP (${(annualMipRate * 100).toStringAsFixed(2)}%)',
                                          value: AmountFormatter.ui(monthlyMip, 'USD'),
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
                                      ? 'FHA requiere 3.5% mínimo. El MIP inicial se financia. El MIP anual es 0.55% si LTV > 95%, 0.50% si LTV ≤ 95%.'
                                      : 'FHA requires 3.5% minimum down. Upfront MIP is financed into the loan. Annual MIP is 0.55% if LTV > 95%, 0.50% if LTV ≤ 95%.',
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
                  ), // Form closes
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

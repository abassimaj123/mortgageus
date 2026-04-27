import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../domain/models/arm_result.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show isSpanishNotifier;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';

class ArmScreen extends ConsumerStatefulWidget {
  const ArmScreen({super.key});
  @override
  ConsumerState<ArmScreen> createState() => _ArmScreenState();
}

class _ArmScreenState extends ConsumerState<ArmScreen> {
  final _loanCtrl    = TextEditingController();
  final _initRateCtrl = TextEditingController(text: '6.0');
  final _adjRateCtrl  = TextEditingController(text: '7.5');
  int _fixedYears    = 5;
  int _termYears     = 30;
  ARMResult? _result;
  String? _loanError;

  final _fmt  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

  static const _fixedOptions = [5, 7, 10];
  static const _termOptions  = [15, 20, 30];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final input = ref.read(mortgageInputProvider);
      final loan  = input.homePrice - (input.homePrice * input.downPaymentPct / 100.0);
      if (loan > 0) {
        _loanCtrl.text = loan.toStringAsFixed(0);
      }
    });
  }

  @override
  void dispose() {
    _loanCtrl.dispose();
    _initRateCtrl.dispose();
    _adjRateCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final loan     = double.tryParse(_loanCtrl.text.replaceAll(',', '')) ?? 0;
    final initRate = double.tryParse(_initRateCtrl.text) ?? 0;
    final adjRate  = double.tryParse(_adjRateCtrl.text)  ?? 0;

    if (loan <= 0) {
      setState(() => _loanError = isSpanishNotifier.value
          ? 'Ingresa un monto de préstamo válido'
          : 'Enter a valid loan amount');
      return;
    }
    setState(() => _loanError = null);

    try {
      final r = MortgageCalculator.calcARM(
        loanAmount:       loan,
        initialRatePct:   initRate,
        fixedYears:       _fixedYears,
        adjustedRatePct:  adjRate,
        totalTermYears:   _termYears,
      );
      setState(() => _result = r);
    } catch (_) {
      setState(() => _result = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        final r = _result;
        return Scaffold(
          appBar: AppBar(title: Text(s.toolArm)),
          body: Column(children: [
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Loan amount ───────────────────────────────────────
                _field(
                  isEs ? 'Monto del Préstamo' : 'Loan Amount',
                  _loanCtrl,
                  prefix: '\$',
                  currency: true,
                  errorText: _loanError,
                ),
                const SizedBox(height: 12),
                // ── Initial rate ──────────────────────────────────────
                _field(
                  isEs ? 'Tasa Inicial (%)' : 'Initial Rate (%)',
                  _initRateCtrl,
                  suffix: '%',
                ),
                const SizedBox(height: 12),
                // ── Fixed period chips ────────────────────────────────
                Text(
                  isEs ? 'Período Fijo' : 'Fixed Period',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(children: _fixedOptions.map((y) {
                  final sel = _fixedYears == y;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      label: '$y year fixed period, ${sel ? "selected" : "not selected"}',
                      child: ChoiceChip(
                        label: Text('${y}yr'),
                        selected: sel,
                        selectedColor: AppTheme.primary,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: sel ? Colors.white : null,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setState(() => _fixedYears = y),
                      ),
                    ),
                  ));
                }).toList()),
                const SizedBox(height: 12),
                // ── Adjusted rate ─────────────────────────────────────
                _field(
                  isEs ? 'Tasa Ajustada después del reset (%)' : 'Adjusted Rate after reset (%)',
                  _adjRateCtrl,
                  suffix: '%',
                ),
                const SizedBox(height: 12),
                // ── Total term ────────────────────────────────────────
                Text(
                  isEs ? 'Plazo Total' : 'Total Term',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(children: _termOptions.map((y) {
                  final sel = _termYears == y;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      label: '$y year total term, ${sel ? "selected" : "not selected"}',
                      child: ChoiceChip(
                        label: Text('${y}yr'),
                        selected: sel,
                        selectedColor: AppTheme.primary,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: sel ? Colors.white : null,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setState(() => _termYears = y),
                      ),
                    ),
                  ));
                }).toList()),
                const SizedBox(height: 20),
                // ── Info note ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    isEs
                        ? 'Una ARM tiene una tasa fija inicial, luego se ajusta. Compara tu pago mensual inicial vs. después del reset.'
                        : 'An ARM has a fixed initial rate, then adjusts. Compare your monthly payment before and after the rate reset.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Calculate button ──────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _calculate,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: Text(
                      isEs ? 'Calcular ARM' : 'Calculate ARM',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                // ── Results ───────────────────────────────────────────
                if (r != null) ...[
                  const SizedBox(height: 24),
                  _ResultCard(r: r, fmt: _fmt, fmtK: _fmtK, s: s, isEs: isEs,
                      fixedYears: _fixedYears, termYears: _termYears),
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

  Widget _field(String label, TextEditingController ctrl, {
    String? prefix, String? suffix, bool currency = false, String? errorText,
  }) {
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

// ── Result card ───────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final ARMResult    r;
  final NumberFormat fmt;
  final NumberFormat fmtK;
  final dynamic      s;
  final bool         isEs;
  final int          fixedYears;
  final int          termYears;
  const _ResultCard({
    required this.r, required this.fmt, required this.fmtK,
    required this.s, required this.isEs,
    required this.fixedYears, required this.termYears,
  });

  @override
  Widget build(BuildContext context) {
    final interestDiff = r.totalInterest - r.fixedTotalInterest;
    final armCheaper   = interestDiff < 0;

    return Column(children: [
      // ── Phase payments ────────────────────────────────────────────
      Row(children: [
        Expanded(child: _PhaseCard(
          label: isEs
              ? 'Pago durante\nperíodo fijo'
              : 'Payment during\nfixed period',
          sublabel: '${fixedYears}yr @ ${s.armMode}',
          value: fmt.format(r.payment1),
          color: AppTheme.primary,
        )),
        const SizedBox(width: 12),
        Expanded(child: _PhaseCard(
          label: isEs ? 'Pago después\ndel reset' : 'Payment after\nreset',
          sublabel: isEs ? 'años ${fixedYears + 1}–$termYears' : 'yr ${fixedYears + 1}–$termYears',
          value: fmt.format(r.payment2),
          color: r.payment2 > r.payment1 ? AppTheme.accentWarn : AppTheme.accentGood,
        )),
      ]),
      const SizedBox(height: 16),
      // ── Detail card ───────────────────────────────────────────────
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _Row(
              isEs ? 'Saldo al reset' : 'Balance at reset',
              fmt.format(r.balanceAtReset),
            ),
            const Divider(height: 20),
            _Row(s.armTotalInterest, fmtK.format(r.totalInterest)),
            _Row(
              isEs ? 'Interés (tasa fija equivalente)' : 'Interest (equivalent fixed rate)',
              fmtK.format(r.fixedTotalInterest),
            ),
            _Row(
              isEs ? 'Diferencia vs. fija' : 'Difference vs. fixed',
              '${armCheaper ? "-" : "+"}${fmtK.format(interestDiff.abs())}',
              color: armCheaper ? AppTheme.accentGood : AppTheme.accentWarn,
              bold: true,
            ),
            const Divider(height: 20),
            // Break-even
            if (r.breakEvenMonths == null)
              _breakEvenBanner(
                isEs ? s.armAlwaysBetter : s.armAlwaysBetter,
                AppTheme.accentGood,
              )
            else
              _breakEvenBanner(
                isEs
                    ? '${s.armCrossesAt} ${r.breakEvenMonths} (${(r.breakEvenMonths! / 12).toStringAsFixed(1)} ${s.years})'
                    : '${s.armCrossesAt} ${r.breakEvenMonths} (${(r.breakEvenMonths! / 12).toStringAsFixed(1)} ${s.years})',
                AppTheme.accentWarn,
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _breakEvenBanner(String text, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
  );
}

class _PhaseCard extends StatelessWidget {
  final String label, sublabel, value;
  final Color  color;
  const _PhaseCard({
    required this.label, required this.sublabel,
    required this.value, required this.color,
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
      const SizedBox(height: 4),
      Text(sublabel,
        textAlign: TextAlign.center,
        style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
      const SizedBox(height: 8),
      Text(value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color, fontWeight: FontWeight.bold, fontSize: 18)),
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
      Expanded(child: Text(label,
        style: const TextStyle(color: Colors.grey, fontSize: 13))),
      Text(value, style: TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        color: color,
        fontSize: 13,
      )),
    ]),
  );
}

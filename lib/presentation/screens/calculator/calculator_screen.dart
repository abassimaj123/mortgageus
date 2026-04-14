import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../domain/models/loan_type.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../providers/mortgage_providers.dart';

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
  bool _advancedExpanded = false;

  final _fmt  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtK = NumberFormat.compactCurrency(locale: 'en_US', symbol: '\$');

  @override
  void dispose() {
    _homePriceCtrl.dispose();
    _downPayCtrl.dispose();
    _rateCtrl.dispose();
    _taxCtrl.dispose();
    _insuranceCtrl.dispose();
    _hoaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result     = ref.watch(mortgageResultProvider);
    final inputState = ref.watch(mortgageInputProvider);
    final notifier   = ref.read(mortgageInputProvider.notifier);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero card ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _HeroCard(result: result),
          ),
          // ── Inputs ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Home Price
                  _buildField('Home Price', _homePriceCtrl, prefix: '\$',
                    currency: true,
                    onChanged: (v) => notifier.updateHomePrice(
                      double.tryParse(v.replaceAll(',', '')) ?? 0)),
                  const SizedBox(height: 12),
                  // Down Payment row
                  _DownPaymentRow(
                    ctrl: _downPayCtrl,
                    notifier: notifier,
                    inputState: inputState,
                  ),
                  const SizedBox(height: 12),
                  // Interest Rate
                  _buildField('Interest Rate', _rateCtrl, suffix: '%',
                    onChanged: (v) => notifier.updateRate(double.tryParse(v) ?? 6.5)),
                  const SizedBox(height: 12),
                  // Term chips
                  _TermSelector(inputState: inputState, notifier: notifier),
                  const SizedBox(height: 12),
                  // Loan type chips
                  _LoanTypeSelector(inputState: inputState, notifier: notifier),
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
                        Text('Advanced options',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          )),
                      ]),
                    ),
                  ),
                  if (_advancedExpanded) ...[
                    const SizedBox(height: 8),
                    _buildField('Property Tax Rate', _taxCtrl, suffix: '%',
                      onChanged: (v) =>
                        notifier.updatePropertyTaxRate(double.tryParse(v) ?? 1.1)),
                    const SizedBox(height: 12),
                    _buildField('Home Insurance', _insuranceCtrl,
                      prefix: '\$', suffix: '/yr',
                      onChanged: (v) =>
                        notifier.updateHomeInsurance(double.tryParse(v) ?? 1750)),
                    const SizedBox(height: 12),
                    _buildField('HOA Fees', _hoaCtrl, prefix: '\$', suffix: '/mo',
                      onChanged: (v) => notifier.updateHoa(double.tryParse(v) ?? 0)),
                  ],
                  const SizedBox(height: 16),
                  // Breakdown card
                  if (result != null)
                    _BreakdownCard(result: result, fmt: _fmt, fmtK: _fmtK),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    String? suffix,
    bool currency = false,
    required Function(String) onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: currency ? [CurrencyInputFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
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
  const _HeroCard({this.result});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly Payment (P&I)',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
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
              'Total PITI: ${fmt.format(result!.monthly.pitiPayment)}',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              _Badge(
                label: result!.isJumbo ? 'Jumbo' : 'Conforming',
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
                const _Badge(label: 'PMI', color: Colors.orange),
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
      color: color.withOpacity(0.2),
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
  const _TermSelector({required this.inputState, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Loan Term', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: MortgageConstants.termPresets.map((term) {
            final selected = inputState.termYears == term;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
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
  const _LoanTypeSelector({required this.inputState, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Loan Type', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: LoanType.values.map((type) {
            final selected = inputState.loanType == type;
            return ChoiceChip(
              label: Text(type.label),
              selected: selected,
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(color: selected ? Colors.white : null),
              onSelected: (_) => notifier.updateLoanType(type),
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
  const _DownPaymentRow({
    required this.ctrl,
    required this.inputState,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Down Payment',
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
  const _BreakdownCard({this.result, required this.fmt, required this.fmtK});

  @override
  Widget build(BuildContext context) {
    final m = result!.monthly;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _Row('Principal',      fmt.format(m.principal)),
          _Row('Interest',       fmt.format(m.interest)),
          _Row('Property Tax',   fmt.format(m.propertyTax)),
          _Row('Home Insurance', fmt.format(m.homeInsurance)),
          if (m.hoa > 0) _Row('HOA', fmt.format(m.hoa)),
          if (m.pmi > 0) _Row(
            'PMI (drops at ${result!.pmiDropMonth ?? "?"}mo)',
            fmt.format(m.pmi),
            color: Colors.orange,
          ),
          const Divider(height: 24),
          _Row('Total PITI', fmt.format(m.pitiPayment), bold: true),
          const SizedBox(height: 8),
          _Row('Total Interest', fmtK.format(result!.totalInterest)),
          _Row('Total Cost',     fmtK.format(result!.totalCost)),
          _Row('Payoff Date',
            '${result!.payoffDate.month}/${result!.payoffDate.year}'),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool   bold;
  final Color? color;
  const _Row(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color ?? Colors.grey.shade700)),
        Text(value, style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: color ?? (bold ? AppTheme.primary : null),
        )),
      ],
    ),
  );
}

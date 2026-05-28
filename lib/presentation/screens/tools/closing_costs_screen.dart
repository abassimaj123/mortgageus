import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/services/analytics_service.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;

/// Closing Costs by State Calculator
///
/// Estimates buyer closing costs based on home price, state, and loan type.
/// All rates are approximations — a disclaimer is shown in the UI.
class ClosingCostsScreen extends StatefulWidget {
  const ClosingCostsScreen({super.key});

  @override
  State<ClosingCostsScreen> createState() => _ClosingCostsScreenState();
}

class _ClosingCostsScreenState extends State<ClosingCostsScreen> {
  final _homePriceCtrl = TextEditingController(text: '400,000');
  final _rateCtrl = TextEditingController(text: '6.9');

  String _state = 'CA';
  String _loanType = 'Conventional';
  bool _isBuyer = true;
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
  }

  @override
  void dispose() {
    _homePriceCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logClosingCostsCalculated();
    final t = await paywallSession.recordAction();
    if (!mounted) return;
    if (t == PaywallTrigger.soft) PaywallSoft.show(context);
    if (t == PaywallTrigger.hard) PaywallHard.show(context);
  }

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

  // State transfer tax rates (as fraction of home price)
  static const Map<String, double> _transferTaxRates = {
    'AL': 0.001,
    'AK': 0.0,
    'AZ': 0.0,
    'AR': 0.0033,
    'CA': 0.0011,
    'CO': 0.0001,
    'CT': 0.0075,
    'DE': 0.04,
    'DC': 0.011,
    'FL': 0.0035,
    'GA': 0.001,
    'HI': 0.01,
    'ID': 0.001,
    'IL': 0.001,
    'IN': 0.001,
    'IA': 0.0016,
    'KS': 0.0,
    'KY': 0.001,
    'LA': 0.0,
    'ME': 0.0044,
    'MD': 0.0075,
    'MA': 0.00456,
    'MI': 0.0075,
    'MN': 0.0033,
    'MS': 0.001,
    'MO': 0.0,
    'MT': 0.0,
    'NE': 0.00225,
    'NV': 0.00195,
    'NH': 0.015,
    'NJ': 0.01,
    'NM': 0.001,
    'NY': 0.01,
    'NC': 0.002,
    'ND': 0.0,
    'OH': 0.001,
    'OK': 0.0,
    'OR': 0.001,
    'PA': 0.02,
    'RI': 0.00228,
    'SC': 0.004,
    'SD': 0.0,
    'TN': 0.00037,
    'TX': 0.0,
    'UT': 0.001,
    'VT': 0.015,
    'VA': 0.0035,
    'WA': 0.0128,
    'WV': 0.011,
    'WI': 0.003,
    'WY': 0.001,
  };

  static const List<String> _allStates = [
    'AL',
    'AK',
    'AZ',
    'AR',
    'CA',
    'CO',
    'CT',
    'DE',
    'DC',
    'FL',
    'GA',
    'HI',
    'ID',
    'IL',
    'IN',
    'IA',
    'KS',
    'KY',
    'LA',
    'ME',
    'MD',
    'MA',
    'MI',
    'MN',
    'MS',
    'MO',
    'MT',
    'NE',
    'NV',
    'NH',
    'NJ',
    'NM',
    'NY',
    'NC',
    'ND',
    'OH',
    'OK',
    'OR',
    'PA',
    'RI',
    'SC',
    'SD',
    'TN',
    'TX',
    'UT',
    'VT',
    'VA',
    'WA',
    'WV',
    'WI',
    'WY',
  ];

  static const List<String> _loanTypes = [
    'Conventional',
    'FHA',
    'VA',
    'USDA',
  ];

  /// Returns list of (label, amount) cost line items
  List<_CostLine> _calcCosts({
    required double homePrice,
    required double rate,
    required String state,
    required String loanType,
  }) {
    if (homePrice <= 0) return [];

    final loanAmount = homePrice * 0.8; // assume 20% down as baseline
    final transferTaxRate = _transferTaxRates[state] ?? 0.001;

    final originationFee = loanAmount * 0.0075;
    const appraisal = 500.0;
    final titleInsurance = homePrice * 0.005;
    const homeInspection = 400.0;
    final transferTax = homePrice * transferTaxRate;
    const recordingFees = 200.0;
    final prePaidInterest =
        rate > 0 ? loanAmount * (rate / 100.0) / 12.0 * 1.0 : 0.0;
    final escrowSetup = homePrice * 0.01 / 12.0 * 3.0 + 150.0 * 3.0;

    final lines = <_CostLine>[
      _CostLine('Origination Fee', 'Tarifa de Originación', originationFee),
      _CostLine('Appraisal', 'Tasación', appraisal),
      _CostLine('Title Insurance', 'Seguro de Título', titleInsurance),
      _CostLine('Home Inspection', 'Inspección del Hogar', homeInspection),
      _CostLine('Transfer Tax ($state)', 'Impuesto de Transferencia ($state)',
          transferTax),
      _CostLine('Recording Fees', 'Tarifas de Registro', recordingFees),
      _CostLine(
          'Prepaid Interest (30d)', 'Interés Prepagado (30d)', prePaidInterest),
      _CostLine('Escrow Setup', 'Configuración de Plica', escrowSetup),
    ];

    // Loan-type specific add-ons
    if (loanType == 'FHA') {
      lines.add(_CostLine(
          'Upfront MIP (1.75%)', 'MIP Inicial (1.75%)', loanAmount * 0.0175));
    } else if (loanType == 'VA') {
      lines.add(_CostLine('VA Funding Fee (2.15%)',
          'Tarifa de Financ. VA (2.15%)', loanAmount * 0.0215));
    } else if (loanType == 'USDA') {
      lines.add(_CostLine('USDA Guarantee Fee (1%)',
          'Tarifa de Garantía USDA (1%)', loanAmount * 0.01));
    }

    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final homePrice = _parse(_homePriceCtrl.text);
        final rate = double.tryParse(_rateCtrl.text) ?? 6.9;
        final lines = _calcCosts(
          homePrice: homePrice,
          rate: rate,
          state: _state,
          loanType: _loanType,
        );
        final total = lines.fold<double>(0.0, (s, l) => s + l.amount);
        final pct = homePrice > 0 ? total / homePrice * 100.0 : 0.0;



        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Costos de Cierre' : 'Closing Costs'),
          ),
          body: Column(children: [
            Expanded(
              child: CalcwisePageEntrance(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Home Price ─────────────────────────────────────
                      _SectionLabel(
                        isEs ? 'Precio de Compra' : 'Home Price',
                        Icons.home_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _homePriceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText:
                              isEs ? 'Precio de la vivienda' : 'Home price',
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
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: isEs
                              ? 'Tasa de interés (%)'
                              : 'Interest Rate (%)',
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

                      // ── State selector ─────────────────────────────────
                      _SectionLabel(
                        isEs ? 'Estado' : 'State',
                        Icons.location_on_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        value: _state,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                        ),
                        items: _allStates
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _state = v);
                            _onInteraction();
                          }
                        },
                      ),

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Loan Type ──────────────────────────────────────
                      _SectionLabel(
                        isEs ? 'Tipo de Préstamo' : 'Loan Type',
                        Icons.account_balance_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: _loanTypes
                            .map((t) => ChoiceChip(
                                  label: Text(t),
                                  selected: _loanType == t,
                                  onSelected: (_) {
                                    setState(() => _loanType = t);
                                    _onInteraction();
                                  },
                                  selectedColor:
                                      AppTheme.primary.withValues(alpha: 0.15),
                                  side: BorderSide(
                                    color: _loanType == t
                                        ? AppTheme.primary
                                        : const Color(0xFFCBD5E1),
                                  ),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _loanType == t
                                        ? AppTheme.primary
                                        : const Color(0xFF64748B),
                                  ),
                                ))
                            .toList(),
                      ),

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Buyer / Seller toggle ──────────────────────────
                      _SectionLabel(
                        isEs ? 'Perspectiva' : 'Perspective',
                        Icons.people_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: _ToggleOption(
                              label: isEs ? 'Comprador' : 'Buyer',
                              selected: _isBuyer,
                              onTap: () {
                                setState(() => _isBuyer = true);
                                _onInteraction();
                              },
                            ),
                          ),
                          Expanded(
                            child: _ToggleOption(
                              label: isEs ? 'Vendedor' : 'Seller',
                              selected: !_isBuyer,
                              onTap: () {
                                setState(() => _isBuyer = false);
                                _onInteraction();
                              },
                            ),
                          ),
                        ]),
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // ── Results ────────────────────────────────────────
                      if (homePrice > 0 && lines.isNotEmpty) ...[
                        // Hero card
                        _HeroCard(
                          label: isEs
                              ? 'Total Estimado'
                              : 'Estimated Closing Costs',
                          value: AmountFormatter.format(total, 'USD'),
                          subValue:
                              '${pct.toStringAsFixed(1)}% ${isEs ? "del precio" : "of home price"}',
                          color: const Color(0xFFEA580C),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Bar chart breakdown
                        _BarChart(lines: lines, total: total, isEs: isEs),
                        const SizedBox(height: AppSpacing.lg),

                        // Line item table
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.mdPlus,
                                  AppSpacing.lg,
                                  AppSpacing.sm),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isEs
                                        ? 'Desglose de costos'
                                        : 'Cost breakdown',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppTextSize.bodyMd),
                                  ),
                                  Text(
                                    isEs ? 'Monto' : 'Amount',
                                    style: const TextStyle(
                                        fontSize: AppTextSize.sm,
                                        color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            ...lines.map((l) => _LineItemRow(
                                  label: isEs ? l.labelEs : l.labelEn,
                                  amount: AmountFormatter.format(l.amount, 'USD'),
                                  pct: total > 0
                                      ? l.amount / total * 100.0
                                      : 0.0,
                                )),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isEs ? 'Total Estimado' : 'Estimated Total',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppTextSize.bodyMd,
                                        color: AppTheme.primary),
                                  ),
                                  Text(
                                    AmountFormatter.format(total, 'USD'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: AppTextSize.bodyMd,
                                        color: AppTheme.primary),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // ── Disclaimer ─────────────────────────────────────
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
                            const Icon(Icons.info_outline,
                                color: AppTheme.infoIcon, size: 18),
                            const SizedBox(width: AppSpacing.smPlus),
                            Expanded(
                              child: Text(
                                isEs
                                    ? 'Solo estimaciones. Los costos reales varían. Consulta con tu prestamista y un agente de bienes raíces.'
                                    : 'Estimates only. Actual costs vary. Consult your lender and a real estate professional.',
                                style: const TextStyle(
                                    color: AppTheme.infoText,
                                    fontSize: AppTextSize.md,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
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

// ── Data model ─────────────────────────────────────────────────────────────────

class _CostLine {
  final String labelEn, labelEs;
  final double amount;
  const _CostLine(this.labelEn, this.labelEs, this.amount);
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SectionLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(text,
            style: const TextStyle(
                fontSize: AppTextSize.bodyMd,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary)),
      ]);
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppTextSize.body,
                color: selected ? AppTheme.primary : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      );
}

class _HeroCard extends StatelessWidget {
  final String label, value, subValue;
  final Color color;
  const _HeroCard({
    required this.label,
    required this.value,
    required this.subValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: AppTextSize.sm)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTextSize.titleMd,
                    fontWeight: FontWeight.w800)),
            Text(subValue,
                style: const TextStyle(
                    color: Colors.white70, fontSize: AppTextSize.sm)),
          ]),
        ]),
      );
}

// ── Simple horizontal bar chart ───────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  final List<_CostLine> lines;
  final double total;
  final bool isEs;

  static const List<Color> _palette = [
    Color(0xFF1B3A6B),
    Color(0xFF0D9488),
    Color(0xFFEA580C),
    Color(0xFF9B59B6),
    Color(0xFF2ECC71),
    Color(0xFFE74C3C),
    Color(0xFF1E3A8A),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFF15803D),
  ];

  const _BarChart({
    required this.lines,
    required this.total,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEs ? 'Distribución de costos' : 'Cost distribution',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: AppTextSize.bodyMd),
          ),
          const SizedBox(height: AppSpacing.md),
          ...lines.asMap().entries.map((e) {
            final idx = e.key;
            final line = e.value;
            final frac = (line.amount / total).clamp(0.0, 1.0);
            final color = _palette[idx % _palette.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          isEs ? line.labelEs : line.labelEn,
                          style: const TextStyle(
                              fontSize: AppTextSize.sm,
                              color: Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(frac * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: AppTextSize.sm,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        Container(
                          height: 8,
                          width: constraints.maxWidth,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          height: 8,
                          width: constraints.maxWidth * frac,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  final String label, amount;
  final double pct;
  const _LineItemRow({
    required this.label,
    required this.amount,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.smPlus),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: AppTextSize.body,
                          color: Color(0xFF334155))),
                  Text('${pct.toStringAsFixed(1)}% of total',
                      style: const TextStyle(
                          fontSize: AppTextSize.xs, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            Text(
              amount,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextSize.body,
                  color: Color(0xFF1E293B)),
            ),
          ],
        ),
      );
}

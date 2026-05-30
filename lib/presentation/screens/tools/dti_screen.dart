import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/services/analytics_service.dart';
import '../../providers/mortgage_providers.dart';
import '../../../../main.dart' show paywallSession, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart' hide CurrencyInputFormatter;

/// DTI (Debt-to-Income) Ratio Calculator
///
/// Front-end DTI = Monthly housing (PITI) / Gross monthly income × 100
/// Back-end DTI  = (Monthly housing + all debts) / Gross monthly income × 100
///
/// Lender thresholds:
///   Conventional: 28% front-end, 36% back-end
///   FHA:          31% front-end, 43% back-end
///   VA/USDA:      41% back-end (flexible front-end)
class DtiScreen extends ConsumerStatefulWidget {
  const DtiScreen({super.key});

  @override
  ConsumerState<DtiScreen> createState() => _DtiScreenState();
}

class _DtiScreenState extends ConsumerState<DtiScreen> {
  late final TextEditingController _annualIncomeCtrl;
  late final TextEditingController _pitiCtrl;
  late final TextEditingController _carPaymentCtrl;
  late final TextEditingController _studentLoansCtrl;
  late final TextEditingController _creditCardsCtrl;
  late final TextEditingController _otherDebtsCtrl;

  bool _logged = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill PITI from main calculator if home price is set
    final input = ref.read(mortgageInputProvider);
    final loanAmt = input.homePrice * (1 - input.downPaymentPct / 100);
    double estimatedPiti = 0;
    if (input.homePrice > 0 && loanAmt > 0) {
      final r = input.annualRatePct / 100 / 12;
      final n = input.termYears * 12;
      if (r > 0 && n > 0) {
        final monthlyPI =
            loanAmt * (r * math.pow(1 + r, n)) / (math.pow(1 + r, n) - 1);
        // Add monthly property tax + insurance estimate
        final monthlyTax =
            input.homePrice * input.propertyTaxRatePct / 100 / 12;
        final monthlyIns = input.homeInsuranceAnnual / 12;
        estimatedPiti = monthlyPI + monthlyTax + monthlyIns;
      }
    }

    _annualIncomeCtrl = TextEditingController(text: '72000');
    _pitiCtrl = TextEditingController(
        text: estimatedPiti > 0
            ? NumberFormat('#,##0').format(estimatedPiti.round())
            : '');
    _carPaymentCtrl = TextEditingController();
    _studentLoansCtrl = TextEditingController();
    _creditCardsCtrl = TextEditingController();
    _otherDebtsCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _annualIncomeCtrl.dispose();
    _pitiCtrl.dispose();
    _carPaymentCtrl.dispose();
    _studentLoansCtrl.dispose();
    _creditCardsCtrl.dispose();
    _otherDebtsCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInteraction() async {
    if (_logged) return;
    _logged = true;
    AnalyticsService.instance.logDtiCalculated();
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
        final annualIncome = _parse(_annualIncomeCtrl.text);
        final monthlyIncome = annualIncome / 12;
        final piti = _parse(_pitiCtrl.text);
        final car = _parse(_carPaymentCtrl.text);
        final student = _parse(_studentLoansCtrl.text);
        final cards = _parse(_creditCardsCtrl.text);
        final other = _parse(_otherDebtsCtrl.text);
        final totalDebts = car + student + cards + other;
        final totalHousing = piti;
        final totalAll = piti + totalDebts;

        final frontEndDti =
            monthlyIncome > 0 ? (totalHousing / monthlyIncome) * 100 : 0.0;
        final backEndDti =
            monthlyIncome > 0 ? (totalAll / monthlyIncome) * 100 : 0.0;

        // Max mortgage at 28% conventional front-end
        final maxMortgagePayment =
            monthlyIncome > 0 ? monthlyIncome * 0.28 : 0.0;



        return Scaffold(
          appBar: AppBar(
            title: Text(isEs ? 'Relación Deuda-Ingreso' : 'DTI Calculator'),
          ),
          body: Column(children: [
            Expanded(
              child: CalcwisePageEntrance(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Income ──────────────────────────────────────────
                      _SectionLabel(isEs ? 'Ingreso' : 'Income',
                          Icons.account_balance_wallet_rounded),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _annualIncomeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: isEs
                              ? 'Ingreso bruto anual'
                              : 'Annual gross income',
                          prefixText: '\$',
                          suffixText: '/yr',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _onInteraction();
                        },
                      ),
                      if (monthlyIncome > 0) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          isEs
                              ? 'Ingreso mensual: ${AmountFormatter.ui(monthlyIncome, 'USD')}'
                              : 'Monthly income: ${AmountFormatter.ui(monthlyIncome, 'USD')}',
                          style: TextStyle(
                              fontSize: AppTextSize.sm,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65)),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.mdPlus),

                      // ── Housing costs ────────────────────────────────────
                      _SectionLabel(
                          isEs
                              ? 'Costos de vivienda (PITI)'
                              : 'Housing Costs (PITI)',
                          Icons.home_rounded),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isEs
                            ? 'Principal + Interés + Impuestos + Seguro'
                            : 'Principal + Interest + Taxes + Insurance',
                        style: TextStyle(
                            fontSize: AppTextSize.sm,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _pitiCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: isEs
                              ? 'Pago mensual PITI'
                              : 'Monthly PITI payment',
                          prefixText: '\$',
                          suffixText: '/mo',
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

                      // ── Monthly debts ────────────────────────────────────
                      _SectionLabel(
                          isEs ? 'Deudas mensuales' : 'Monthly Debt Payments',
                          Icons.credit_card_rounded),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        Expanded(
                          child: _DebtField(
                            ctrl: _carPaymentCtrl,
                            label: isEs ? 'Auto' : 'Car',
                            icon: Icons.directions_car_rounded,
                            onChanged: (_) {
                              setState(() {});
                              _onInteraction();
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _DebtField(
                            ctrl: _studentLoansCtrl,
                            label: isEs ? 'Estudiantil' : 'Student loan',
                            icon: Icons.school_rounded,
                            onChanged: (_) {
                              setState(() {});
                              _onInteraction();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        Expanded(
                          child: _DebtField(
                            ctrl: _creditCardsCtrl,
                            label: isEs ? 'Tarjetas' : 'Credit cards',
                            icon: Icons.credit_card_rounded,
                            onChanged: (_) {
                              setState(() {});
                              _onInteraction();
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _DebtField(
                            ctrl: _otherDebtsCtrl,
                            label: isEs ? 'Otras deudas' : 'Other debts',
                            icon: Icons.more_horiz_rounded,
                            onChanged: (_) {
                              setState(() {});
                              _onInteraction();
                            },
                          ),
                        ),
                      ]),

                      const SizedBox(height: AppSpacing.lg),

                      // ── Results ──────────────────────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: monthlyIncome <= 0
                            ? Center(
                                key: const ValueKey('empty'),
                                child: Text(
                                  isEs
                                      ? 'Ingresa tu ingreso anual para ver resultados'
                                      : 'Enter your annual income to see results',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.65),
                                      fontSize: AppTextSize.md),
                                ),
                              )
                            : Column(
                                key: const ValueKey('results'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // DTI gauges
                                  _DtiGauge(
                                    label: isEs
                                        ? 'DTI Front-End'
                                        : 'Front-End DTI',
                                    subtitle: isEs
                                        ? 'Solo vivienda / ingreso'
                                        : 'Housing only / income',
                                    dti: frontEndDti,
                                    goodThreshold: 28,
                                    warnThreshold: 36,
                                    isEs: isEs,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _DtiGauge(
                                    label:
                                        isEs ? 'DTI Back-End' : 'Back-End DTI',
                                    subtitle: isEs
                                        ? 'Vivienda + todas las deudas / ingreso'
                                        : 'Housing + all debts / income',
                                    dti: backEndDti,
                                    goodThreshold: 36,
                                    warnThreshold: 43,
                                    isEs: isEs,
                                  ),
                                  const SizedBox(height: AppSpacing.md),

                                  // Lender verdicts
                                  _LenderVerdictsCard(
                                    frontEnd: frontEndDti,
                                    backEnd: backEndDti,
                                    isEs: isEs,
                                  ),
                                  const SizedBox(height: AppSpacing.md),

                                  // Max mortgage payment
                                  if (maxMortgagePayment > 0)
                                    Container(
                                      width: double.infinity,
                                      padding:
                                          const EdgeInsets.all(AppSpacing.lg),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceTint,
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.lg),
                                        border: Border.all(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isEs
                                                ? 'Pago máximo de hipoteca (28% front-end)'
                                                : 'Max mortgage payment at 28% front-end',
                                            style: const TextStyle(
                                              fontSize: AppTextSize.sm,
                                              color: AppTheme.labelGray,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            '${AmountFormatter.ui(maxMortgagePayment, 'USD')}/mo',
                                            style: const TextStyle(
                                              fontSize: AppTextSize.titleMd,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            isEs
                                                ? 'Basado en tu ingreso mensual de ${AmountFormatter.ui(monthlyIncome, 'USD')}'
                                                : 'Based on your monthly income of ${AmountFormatter.ui(monthlyIncome, 'USD')}',
                                            style: const TextStyle(
                                                fontSize: AppTextSize.xs,
                                                color: AppTheme.labelGray),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Info box
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
                                    ? 'El DTI es uno de los principales criterios de elegibilidad hipotecaria. Los prestamistas pueden aprobar ratios más altos con compensadores como excelente crédito o grandes reservas.'
                                    : 'DTI is a primary mortgage qualification criteria. Lenders may approve higher ratios with compensating factors like excellent credit or large reserves.',
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

// ── DTI Gauge ─────────────────────────────────────────────────────────────────

class _DtiGauge extends StatelessWidget {
  final String label, subtitle;
  final double dti, goodThreshold, warnThreshold;
  final bool isEs;

  const _DtiGauge({
    required this.label,
    required this.subtitle,
    required this.dti,
    required this.goodThreshold,
    required this.warnThreshold,
    required this.isEs,
  });

  Color _colorFor(Brightness b) {
    if (dti <= goodThreshold) return CalcwiseSemanticColors.success(b);
    if (dti <= warnThreshold) return AppTheme.accentWarn;
    return CalcwiseSemanticColors.error(b);
  }

  String get _verdict {
    if (dti <= goodThreshold) return isEs ? 'Excelente' : 'Excellent';
    if (dti <= warnThreshold) return isEs ? 'Aceptable' : 'Acceptable';
    return isEs ? 'Alto' : 'High';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(Theme.of(context).brightness);
    final pct = dti.clamp(0.0, 70.0);
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
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTextSize.bodyMd)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: AppTextSize.sm,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65))),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '${dti.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    _verdict,
                    style: TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ]),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 70).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Threshold labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%',
                  style: const TextStyle(
                      fontSize: AppTextSize.xs, color: Color(0xFF94A3B8))),
              Text('${goodThreshold.toInt()}%',
                  style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: CalcwiseSemanticColors.success(
                          Theme.of(context).brightness),
                      fontWeight: FontWeight.w600)),
              Text('${warnThreshold.toInt()}%',
                  style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: AppTheme.accentWarn,
                      fontWeight: FontWeight.w600)),
              Text('70%+',
                  style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: CalcwiseSemanticColors.error(
                          Theme.of(context).brightness),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Lender Verdicts Card ──────────────────────────────────────────────────────

class _LenderVerdictsCard extends StatelessWidget {
  final double frontEnd, backEnd;
  final bool isEs;

  const _LenderVerdictsCard({
    required this.frontEnd,
    required this.backEnd,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final verdicts = [
      _LenderVerdict(
        name: 'Conventional',
        maxFront: 28,
        maxBack: 36,
        frontEnd: frontEnd,
        backEnd: backEnd,
        isEs: isEs,
      ),
      _LenderVerdict(
        name: 'FHA',
        maxFront: 31,
        maxBack: 43,
        frontEnd: frontEnd,
        backEnd: backEnd,
        isEs: isEs,
      ),
      _LenderVerdict(
        name: isEs ? 'VA / USDA' : 'VA / USDA',
        maxFront: 50, // flexible — no firm limit
        maxBack: 41,
        frontEnd: frontEnd,
        backEnd: backEnd,
        isEs: isEs,
        flexFront: true,
      ),
    ];

    return Container(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.mdPlus, AppSpacing.lg, AppSpacing.sm),
            child: Text(
              isEs
                  ? 'Elegibilidad por tipo de préstamo'
                  : 'Lender eligibility by loan type',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: AppTextSize.bodyMd),
            ),
          ),
          const Divider(height: 1),
          ...verdicts.map((v) => v),
        ],
      ),
    );
  }
}

class _LenderVerdict extends StatelessWidget {
  final String name;
  final double maxFront, maxBack, frontEnd, backEnd;
  final bool isEs, flexFront;

  const _LenderVerdict({
    required this.name,
    required this.maxFront,
    required this.maxBack,
    required this.frontEnd,
    required this.backEnd,
    required this.isEs,
    this.flexFront = false,
  });

  bool get _passes {
    final frontOk = flexFront || frontEnd <= maxFront;
    final backOk = backEnd <= maxBack;
    return frontOk && backOk;
  }

  @override
  Widget build(BuildContext context) {
    final passes = _passes;
    // Icon sits on the neutral row surface → theme-aware so it stays visible
    // in dark mode.
    final iconColor = passes
        ? CalcwiseSemanticColors.success(Theme.of(context).brightness)
        : CalcwiseSemanticColors.error(Theme.of(context).brightness);
    // Badge text lives inside the fixed-light successBg/errorBg → keep the dark
    // shade so the bg+text pair stays readable.
    final badgeTextColor = passes
        ? CalcwiseSemanticColors.successDark
        : CalcwiseSemanticColors.errorDark;
    final bg = passes
        ? CalcwiseSemanticColors.successBg
        : CalcwiseSemanticColors.errorBg;
    final icon = passes ? Icons.check_circle_outline : Icons.cancel_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.smPlus),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: AppTextSize.body)),
            Text(
              flexFront
                  ? (isEs
                      ? 'Front-end flexible · Back-end ≤ ${maxBack.toInt()}%'
                      : 'Flexible front-end · Back-end ≤ ${maxBack.toInt()}%')
                  : (isEs
                      ? 'Front ≤ ${maxFront.toInt()}% · Back ≤ ${maxBack.toInt()}%'
                      : 'Front ≤ ${maxFront.toInt()}% · Back ≤ ${maxBack.toInt()}%'),
              style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65)),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            passes
                ? (isEs ? 'Aprobado' : 'Eligible')
                : (isEs ? 'Muy alto' : 'Too high'),
            style: TextStyle(
                fontSize: AppTextSize.xs,
                fontWeight: FontWeight.w700,
                color: badgeTextColor),
          ),
        ),
      ]),
    );
  }
}

// ── Debt field ─────────────────────────────────────────────────────────────────

class _DebtField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _DebtField({
    required this.ctrl,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [CurrencyInputFormatter()],
        decoration: InputDecoration(
          labelText: label,
          prefixText: '\$',
          prefixIcon: Icon(icon, size: 17),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md),
        ),
        onChanged: onChanged,
      );
}

// ── Section label ─────────────────────────────────────────────────────────────

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

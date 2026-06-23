import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../providers/mortgage_providers.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart' show isSpanishNotifier, tabSwitchNotifier;
import 'history_screen.dart' show HistoryScreen;
import 'package:calcwise_core/calcwise_core.dart';
import '../../widgets/paywall_hard.dart';
import '../../../core/services/analytics_service.dart';

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> row;

  const HistoryDetailScreen({super.key, required this.row});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final _fmtDate = DateFormat('MMMM d, yyyy – HH:mm');

  // ── Helpers ────────────────────────────────────────────────────────────────

  LoanType _parseLoanType(String label) {
    switch (label) {
      case 'FHA':
        return LoanType.fha;
      case 'VA':
        return LoanType.va;
      case 'Jumbo':
        return LoanType.jumbo;
      default:
        return LoanType.conventional;
    }
  }

  void _loadIntoCalculator(BuildContext context) {
    final row = widget.row;
    final homePrice = (row['home_price'] as num?)?.toDouble() ?? 0.0;
    final downPercent = (row['down_percent'] as num?)?.toDouble() ?? 20.0;
    final annualRate = (row['annual_rate'] as num?)?.toDouble() ?? 6.5;
    final termYears = (row['term_years'] as num?)?.toInt() ?? 30;
    final taxRate = (row['tax_rate'] as num?)?.toDouble() ?? MortgageConstants.defaultPropertyTaxRate;
    final insurance = (row['insurance'] as num?)?.toDouble() ?? MortgageConstants.defaultHomeInsurance;
    final hoa = (row['hoa'] as num?)?.toDouble() ?? 0.0;
    final loanType = _parseLoanType(row['loan_type'] as String? ?? 'Conventional');

    final notifier = ProviderScope.containerOf(context).read(mortgageInputProvider.notifier);
    notifier.updateHomePrice(homePrice);
    notifier.updateDownPaymentPct(downPercent);
    notifier.updateRate(annualRate);
    notifier.updateTerm(termYears);
    notifier.updateLoanType(loanType);
    notifier.updatePropertyTaxRate(taxRate);
    notifier.updateHomeInsurance(insurance);
    notifier.updateHoa(hoa);

    tabSwitchNotifier.value = 0; // switch to Calculator tab
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _delete(bool isEs) async {
    final id = widget.row['id'] as int? ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEs ? '¿Eliminar entrada?' : 'Delete entry?'),
        content: Text(isEs
            ? 'Este cálculo será eliminado permanentemente del historial.'
            : 'This calculation will be permanently removed from history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEs ? 'Eliminar' : 'Delete',
                style: TextStyle(
                    color: CalcwiseSemanticColors.error(
                        Theme.of(ctx).brightness))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.deleteHistory(id);
      HistoryScreen.refreshNotifier.value++;
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _exportPdf(BuildContext context, bool isEs) async {
    final row = widget.row;
    final homePrice = (row['home_price'] as num?)?.toDouble() ?? 0.0;
    final downPercent = (row['down_percent'] as num?)?.toDouble() ?? 20.0;
    final annualRate = (row['annual_rate'] as num?)?.toDouble() ?? 6.5;
    final termYears = (row['term_years'] as num?)?.toInt() ?? 30;
    final taxRate = (row['tax_rate'] as num?)?.toDouble() ??
        MortgageConstants.defaultPropertyTaxRate;
    final insurance = (row['insurance'] as num?)?.toDouble() ??
        MortgageConstants.defaultHomeInsurance;
    final hoa = (row['hoa'] as num?)?.toDouble() ?? 0.0;
    final loanType =
        _parseLoanType(row['loan_type'] as String? ?? 'Conventional');

    final downPayment = homePrice * downPercent / 100.0;
    final loanAmount = homePrice - downPayment;
    final ltv = homePrice > 0 ? loanAmount / homePrice * 100 : 0.0;
    final pmiRate = (ltv > 80.0 && loanType != LoanType.va)
        ? MortgageConstants.pmiDefaultAnnualRate * 100
        : 0.0;

    final inputState = MortgageInputState(
      homePrice: homePrice,
      downPaymentPct: downPercent,
      annualRatePct: annualRate,
      termYears: termYears,
      loanType: loanType,
      propertyTaxRatePct: taxRate,
      homeInsuranceAnnual: insurance,
      hoaMonthly: hoa,
    );

    final now = DateTime.now();
    final input = MortgageInput(
      homePrice: homePrice,
      downPayment: downPayment,
      annualRatePct: annualRate,
      termYears: termYears,
      loanType: loanType,
      propertyTaxRatePct: taxRate,
      homeInsuranceAnnual: insurance,
      hoaMonthly: hoa,
      pmiAnnualRatePct: pmiRate,
      startDate: DateTime(now.year, now.month + 1),
    );

    try {
      final result = MortgageCalculator.calculate(input);
      if (context.mounted) {
        await PdfExportService.exportMortgage(context, inputState, result,
            isEs: isEs);
      }
    } catch (e) {
      if (context.mounted) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.exportFailed}: $e')),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final row = widget.row;
        final homePrice = (row['home_price'] as num?)?.toDouble() ?? 0.0;
        final downPercent = (row['down_percent'] as num?)?.toDouble() ?? 20.0;
        final annualRate = (row['annual_rate'] as num?)?.toDouble() ?? 0.0;
        final termYears = (row['term_years'] as num?)?.toInt() ?? 30;
        final loanType = row['loan_type'] as String? ?? 'Conventional';
        final loanAmount = (row['loan_amount'] as num?)?.toDouble() ?? 0.0;
        final monthlyPayment =
            (row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
        final totalInterest =
            (row['total_interest'] as num?)?.toDouble() ?? 0.0;
        final taxRate = (row['tax_rate'] as num?)?.toDouble() ?? 0.0;
        final insurance = (row['insurance'] as num?)?.toDouble() ?? 0.0;
        final hoa = (row['hoa'] as num?)?.toDouble() ?? 0.0;
        final totalCost = totalInterest + loanAmount;
        final downAmount = homePrice * downPercent / 100;

        // Recompute P&I from stored inputs (not persisted directly in DB)
        final piPayment = loanAmount > 0 && annualRate > 0 && termYears > 0
            ? MortgageCalculator.calcMonthlyPayment(
                loanAmount: loanAmount,
                annualRatePct: annualRate,
                termYears: termYears,
              )
            : 0.0;
        final createdAt =
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now();

        return Scaffold(
          appBar: AppBar(
            title: Text(_fmtDate.format(createdAt.toLocal()),
                style: const TextStyle(fontSize: AppTextSize.body)),
            actions: [
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: CalcwiseSemanticColors.error(
                        Theme.of(context).brightness)),
                tooltip: isEs ? 'Eliminar' : 'Delete',
                onPressed: () => _delete(isEs),
              ),
            ],
          ),
          body: CalcwisePageEntrance(
            child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      // ── Inputs card ───────────────────────────────────────
                      _SectionCard(
                        title: isEs ? 'Parámetros' : 'Inputs',
                        icon: Icons.input_rounded,
                        children: [
                          _Row(isEs ? 'Precio de la casa' : 'Home Price',
                              AmountFormatter.ui(homePrice, 'USD')),
                          _Row(isEs ? 'Enganche' : 'Down Payment',
                              '${downPercent.toStringAsFixed(1)}% (${AmountFormatter.ui(downAmount, 'USD')})'),
                          _Row(isEs ? 'Tasa anual' : 'Annual Rate',
                              '${annualRate.toStringAsFixed(2)}%'),
                          _Row(isEs ? 'Plazo' : 'Loan Term',
                              '$termYears ${isEs ? 'años' : 'years'}'),
                          _Row(isEs ? 'Tipo de préstamo' : 'Loan Type',
                              loanType),
                          _Row(isEs ? 'Monto del préstamo' : 'Loan Amount',
                              AmountFormatter.ui(loanAmount, 'USD')),
                          if (taxRate > 0)
                            _Row(
                                isEs
                                    ? 'Impuesto predial'
                                    : 'Property Tax Rate',
                                '${taxRate.toStringAsFixed(2)}%'),
                          if (insurance > 0)
                            _Row(isEs ? 'Seguro' : 'Home Insurance',
                                AmountFormatter.ui(insurance, 'USD')),
                          if (hoa > 0)
                            _Row(isEs ? 'HOA mensual' : 'HOA Monthly',
                                AmountFormatter.ui(hoa, 'USD')),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── Results card ──────────────────────────────────────
                      _SectionCard(
                        title: isEs ? 'Resultados' : 'Results',
                        icon: Icons.bar_chart_rounded,
                        children: [
                          if (piPayment > 0)
                            _Row(
                              isEs ? 'Capital + Interés (P&I)' : 'P&I (Principal + Interest)',
                              AmountFormatter.ui(piPayment, 'USD'),
                            ),
                          _Row(
                            isEs
                                ? 'Pago mensual (PITI)'
                                : 'Monthly Payment (PITI)',
                            AmountFormatter.ui(monthlyPayment, 'USD'),
                            highlight: AppTheme.primary,
                            bold: true,
                          ),
                          _Row(isEs ? 'Interés total' : 'Total Interest',
                              AmountFormatter.ui(totalInterest, 'USD')),
                          _Row(isEs ? 'Costo total' : 'Total Cost',
                              AmountFormatter.ui(totalCost, 'USD'),
                              bold: true),
                        ],
                      ),
                    ],
                  ),
                ),
                _BottomBar(
                  isEs: isEs,
                  onExport: () => _exportPdf(context, isEs),
                  onLoadIntoCalculator: () => _loadIntoCalculator(context),
                ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }
}

// ── Bottom bar ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final bool isEs;
  final Future<void> Function() onExport;
  final VoidCallback onLoadIntoCalculator;

  const _BottomBar({
    required this.isEs,
    required this.onExport,
    required this.onLoadIntoCalculator,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.hasFullAccessNotifier,
      builder: (_, isPremium, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isPremium ? AppTheme.primary : CalcwiseTheme.of(context).surfaceHigh,
                  foregroundColor:
                      isPremium ? Colors.white : CalcwiseTheme.of(context).textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                  side: isPremium
                      ? BorderSide.none
                      : BorderSide(color: CalcwiseTheme.of(context).cardBorder),
                ),
                icon: Icon(
                    isPremium
                        ? Icons.picture_as_pdf_rounded
                        : Icons.lock_rounded,
                    size: 20),
                label: Text(
                    isEs ? 'Exportar PDF' : 'Export PDF',
                    style: const TextStyle(
                        fontSize: AppTextSize.body,
                        fontWeight: FontWeight.w600)),
                onPressed: () async {
                  if (!isPremium && !freemiumService.isRewarded) {
                    if (context.mounted) await PaywallHard.show(context);
                    return;
                  }
                  if (!context.mounted) return;
                  await onExport();
                  try {
                    AnalyticsService.instance.logExportStarted();
                  } catch (_) {}
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(
                  isEs ? 'Cargar en calculadora' : 'Load into Calculator',
                  style: const TextStyle(
                      fontSize: AppTextSize.body, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                ),
                onPressed: onLoadIntoCalculator,
              ),
            ),
          ),
          if (!isPremium) const CalcwiseAdFooter(),
        ],
      ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyMd,
                      color: AppTheme.primary)),
            ]),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? highlight;
  final bool bold;

  const _Row(this.label, this.value, {this.highlight, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65))),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(value,
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                    color: highlight)),
          ],
        ),
      );
}

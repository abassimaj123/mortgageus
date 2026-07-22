import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../extra_payments/extra_payments_screen.dart';
import '../refinance/refinance_screen.dart';
import '../../../../main.dart';
import 'arm_screen.dart';
import 'investment_return_screen.dart';
import 'pmi_screen.dart';
import 'fha_screen.dart';
import 'va_screen.dart';
import 'usda_screen.dart';
import 'pmi_calculator_screen.dart';
import 'points_screen.dart';
import 'dti_screen.dart';
import 'heloc_calc_screen.dart';
import 'closing_costs_screen.dart';
import '../affordability/affordability_screen.dart';
import '../../../core/services/analytics_service.dart';
import 'package:calcwise_core/calcwise_core.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});
  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('tools');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        final sectionMyDecision =
            isEs ? 'Mi Decisión' : 'My Decision';
        final sectionLoanTypes =
            isEs ? 'Tipos de Préstamo' : 'Loan Types';
        final sectionCosts = isEs ? 'Costos' : 'Costs';
        final tools = [
          _ToolItem(
            section: sectionMyDecision,
            icon: Icons.home_work_rounded,
            iconSelected: Icons.home_work,
            color: AppTheme.primary,
            title: s.affordTitle,
            subtitle: isEs
                ? 'Presupuesto máximo según tus ingresos'
                : 'Max budget based on your income',
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const AffordabilityScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionMyDecision,
            icon: Icons.add_circle_outline,
            iconSelected: Icons.add_circle,
            color: AppTheme.primary,
            title: s.toolExtra,
            subtitle: s.toolExtraSub,
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const ExtraPaymentsScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionMyDecision,
            icon: Icons.balance_rounded,
            iconSelected: Icons.balance,
            color: const Color(0xFF0891B2), // cyan-600
            title: isEs
                ? 'Deuda-Ingreso (¿Califico?)'
                : 'Debt-to-Income (Can I Qualify?)',
            subtitle: isEs
                ? 'Verifica tu elegibilidad con prestamistas'
                : 'Check lender eligibility & max payment',
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const DtiScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionMyDecision,
            icon: Icons.refresh_rounded,
            iconSelected: Icons.refresh_rounded,
            color: AppTheme.toolRefi,
            title: s.toolRefi,
            subtitle: s.toolRefiSub,
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const RefinanceScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionCosts,
            icon: Icons.security_rounded,
            iconSelected: Icons.security,
            color: AppTheme.toolPmi,
            title: isEs ? 'Estimado de PMI' : 'PMI Estimate',
            subtitle: isEs
                ? 'Estimación rápida: precio y pago inicial'
                : 'Quick estimate from home price & down payment',
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const PmiScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionLoanTypes,
            icon: Icons.swap_horiz_rounded,
            iconSelected: Icons.swap_horiz,
            color: AppTheme.toolRefi,
            title: s.toolArm,
            subtitle: s.toolArmSub,
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const ArmScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionMyDecision,
            icon: Icons.trending_up_rounded,
            iconSelected: Icons.trending_up,
            color: AppTheme.toolInvestment,
            title: s.toolInvestment,
            subtitle: s.toolInvestmentSub,
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const InvestmentReturnScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionLoanTypes,
            icon: Icons.home_rounded,
            iconSelected: Icons.home_rounded,
            color: AppTheme.toolFha,
            title: isEs ? 'Préstamo FHA' : 'FHA Loan',
            subtitle: isEs
                ? 'Calcula MIP y pago total FHA'
                : 'Calculate MIP and total FHA payment',
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const FhaScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
          ),
          _ToolItem(
            section: sectionLoanTypes,
            icon: Icons.military_tech_rounded,
            iconSelected: Icons.military_tech,
            color: AppTheme.toolVa,
            title: isEs ? 'Préstamo VA' : 'VA Loan',
            subtitle: isEs
                ? 'Tarifa de financiación y pago VA'
                : 'Funding fee and VA monthly payment',
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const VaScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
          ),
          _ToolItem(
            section: sectionLoanTypes,
            icon: Icons.agriculture_rounded,
            iconSelected: Icons.agriculture,
            color: AppTheme.toolUsda,
            title: isEs ? 'Préstamo USDA' : 'USDA Loan',
            subtitle: isEs
                ? 'Préstamo rural con 0% inicial'
                : 'Rural loan with 0% down',
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const UsdaScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
          ),
          _ToolItem(
            section: sectionCosts,
            icon: Icons.shield_rounded,
            iconSelected: Icons.shield,
            color: AppTheme.toolPmiDetail,
            title: isEs
                ? 'PMI por puntaje crediticio y LTV'
                : 'PMI by Credit Score & LTV',
            subtitle: isEs
                ? 'Tasa exacta según tu puntaje crediticio y LTV'
                : 'Exact rate based on your credit score and LTV',
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const PmiCalculatorScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
          ),
          _ToolItem(
            section: sectionMyDecision,
            icon: Icons.percent_rounded,
            iconSelected: Icons.percent,
            color: AppTheme.toolPoints,
            title: isEs ? 'Puntos de descuento' : 'Discount Points',
            subtitle: isEs
                ? 'Equilibrio y ahorro de comprar puntos'
                : 'Breakeven and lifetime savings',
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const PointsScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
          ),
          _ToolItem(
            section: sectionCosts,
            icon: Icons.account_balance_rounded,
            iconSelected: Icons.account_balance,
            color: Color(0xFF0D9488), // teal
            title: isEs ? 'Calculadora HELOC' : 'HELOC Calculator',
            subtitle: isEs
                ? 'Línea de crédito sobre el capital de tu hogar'
                : 'Home equity line of credit estimator',
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const HelocCalcScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
          _ToolItem(
            section: sectionCosts,
            icon: Icons.receipt_long_rounded,
            iconSelected: Icons.receipt_long,
            color: Color(0xFFEA580C), // deep orange
            title: isEs ? 'Costos de Cierre' : 'Closing Costs by State',
            subtitle: isEs
                ? 'Estima costos de cierre por estado'
                : 'Estimate closing costs by US state',
            onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const ClosingCostsScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
          ),
        ];

        // Group tools by section, preserving the order sections first appear in.
        final sections = <String>[];
        final bySection = <String, List<_ToolItem>>{};
        for (final t in tools) {
          (bySection[t.section] ??= []).add(t);
          if (!sections.contains(t.section)) sections.add(t.section);
        }

        return Scaffold(
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: SingleChildScrollView(
            key: const PageStorageKey('tools_hub'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                for (final section in sections) ...[
                  _ToolSectionHeader(title: section),
                  ...bySection[section]!.map((t) => _ToolCard(item: t)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolSectionHeader extends StatelessWidget {
  final String title;
  const _ToolSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: AppTextSize.xs,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.0,
          ),
        ),
      );
}

class _ToolItem {
  final String section;
  final IconData icon, iconSelected;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;

  const _ToolItem({
    required this.section,
    required this.icon,
    required this.iconSelected,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _ToolCard extends StatelessWidget {
  final _ToolItem item;
  const _ToolCard({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Icon(item.icon, color: item.color, size: 24),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(item.subtitle,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65),
                              fontSize: AppTextSize.sm)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant, size: 22),
              ],
            ),
          ),
        ),
      );
}

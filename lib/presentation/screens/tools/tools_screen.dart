import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../extra_payments/extra_payments_screen.dart';
import '../refinance/refinance_screen.dart';
import '../history/history_screen.dart';
import '../../../../main.dart';
import 'arm_screen.dart';
import 'investment_return_screen.dart';
import 'pmi_screen.dart';
import 'fha_screen.dart';
import 'va_screen.dart';
import 'usda_screen.dart';
import 'pmi_calculator_screen.dart';
import 'points_screen.dart';
import 'package:calcwise_core/calcwise_core.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        final tools = [
          _ToolItem(
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
            icon: Icons.security_rounded,
            iconSelected: Icons.security,
            color: AppTheme.toolPmi,
            title: isEs ? 'Calculadora PMI' : 'PMI Calculator',
            subtitle: isEs
                ? 'Calcula tu seguro hipotecario'
                : 'Calculate your mortgage insurance',
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
            icon: Icons.shield_rounded,
            iconSelected: Icons.shield,
            color: AppTheme.toolPmiDetail,
            title: isEs ? 'PMI detallado' : 'PMI Detail',
            subtitle: isEs
                ? 'Tasa por puntaje crediticio y LTV'
                : 'Rate by credit score and LTV',
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
            icon: Icons.history_rounded,
            iconSelected: Icons.history,
            color: AppTheme.toolHistory,
            title: s.toolHistory,
            subtitle: s.toolHistorySub,
            onTap: () {
              HistoryScreen.refreshNotifier.value++;
              Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const HistoryScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                ),
              );
            },
          ),
        ];

        return Scaffold(
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: SingleChildScrollView(
            key: const PageStorageKey('tools_hub'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                ...tools.map((t) => _ToolCard(item: t)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolItem {
  final IconData icon, iconSelected;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;

  const _ToolItem({
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
                  color: Colors.black.withValues(alpha: 0.06),
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
                              color: Color(0xFF64748B),
                              fontSize: AppTextSize.sm)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: const Color(0xFF94A3B8), size: 22),
              ],
            ),
          ),
        ),
      );
}

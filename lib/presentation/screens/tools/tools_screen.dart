import 'package:flutter/material.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import '../extra_payments/extra_payments_screen.dart';
import '../refinance/refinance_screen.dart';
import '../history/history_screen.dart';
import '../../../../main.dart';
import 'arm_screen.dart';
import 'pmi_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        final tools = [
          _ToolItem(
            icon: Icons.add_circle_outline,
            iconSelected: Icons.add_circle,
            color: AppTheme.primary,
            title: s.toolExtra,
            subtitle: s.toolExtraSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExtraPaymentsScreen()),
            ),
          ),
          _ToolItem(
            icon: Icons.refresh_outlined,
            iconSelected: Icons.refresh,
            color: AppTheme.toolRefi,
            title: s.toolRefi,
            subtitle: s.toolRefiSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RefinanceScreen()),
            ),
          ),
          _ToolItem(
            icon: Icons.history_outlined,
            iconSelected: Icons.history,
            color: AppTheme.toolHistory,
            title: s.toolHistory,
            subtitle: s.toolHistorySub,
            onTap: () {
              HistoryScreen.refreshNotifier.value++;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          _ToolItem(
            icon: Icons.security_outlined,
            iconSelected: Icons.security,
            color: AppTheme.toolPmi,
            title: isEs ? 'Calculadora PMI' : 'PMI Calculator',
            subtitle: isEs
                ? 'Calcula tu seguro hipotecario'
                : 'Calculate your mortgage insurance',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PmiScreen()),
            ),
          ),
          _ToolItem(
            icon: Icons.swap_horiz_outlined,
            iconSelected: Icons.swap_horiz,
            color: AppTheme.toolRefi,
            title: s.toolArm,
            subtitle: s.toolArmSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArmScreen()),
            ),
          ),
        ];

        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      ...tools.map((t) => _ToolCard(item: t)),
                    ],
                  ),
                ),
              ),
              const AdFooter(),
            ],
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
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(item.subtitle,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 22),
              ],
            ),
          ),
        ),
      );
}

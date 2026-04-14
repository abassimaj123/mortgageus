import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/mortgage_providers.dart';

class AmortizationScreen extends ConsumerWidget {
  const AmortizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(mortgageResultProvider);
    if (result == null) {
      return const Scaffold(
        body: Center(child: Text('Enter loan details in Calculator tab')));
    }
    final fmt      = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
    final schedule = result.schedule;

    return Scaffold(
      appBar: AppBar(title: const Text('Amortization Schedule')),
      body: CustomScrollView(slivers: [
        // Pie chart
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('Life of Loan Breakdown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: PieChart(PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: result.loanAmount,
                          title: 'Principal\n${fmt.format(result.loanAmount)}',
                          color: AppTheme.primary,
                          radius: 80,
                          titleStyle: const TextStyle(
                            color: Colors.white, fontSize: 11),
                        ),
                        PieChartSectionData(
                          value: result.totalInterest,
                          title: 'Interest\n${fmt.format(result.totalInterest)}',
                          color: AppTheme.secondary,
                          radius: 80,
                          titleStyle: const TextStyle(
                            color: Colors.white, fontSize: 11),
                        ),
                      ],
                      centerSpaceRadius: 0,
                    )),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Legend(color: AppTheme.primary, label: 'Principal'),
                    const SizedBox(width: 24),
                    _Legend(color: AppTheme.secondary, label: 'Interest'),
                  ]),
                ]),
              ),
            ),
          ),
        ),
        // Summary row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _SummaryChip('Total Interest', fmt.format(result.totalInterest),
                color: Colors.orange),
              const SizedBox(width: 8),
              _SummaryChip('Total Cost', fmt.format(result.totalCost),
                color: AppTheme.primary),
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // Table header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TableHeader(),
          ),
        ),
        // Lazy list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final e      = schedule[i];
              final isOdd  = i % 2 == 0;
              final bgColor = e.pmiDropped
                  ? Colors.orange.shade50
                  : isOdd ? Colors.grey.shade50 : Colors.white;
              return Container(
                color: bgColor,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  _Cell('${e.month}',               flex: 1),
                  _Cell('${e.date.month}/${e.date.year}', flex: 2),
                  _Cell(fmt.format(e.payment),      flex: 2),
                  _Cell(fmt.format(e.principal),    flex: 2),
                  _Cell(fmt.format(e.interest),     flex: 2),
                  _Cell(fmt.format(e.balance),      flex: 2),
                ]),
              );
            },
            childCount: schedule.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color  color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 14, height: 14, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 13)),
  ]);
}

class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _SummaryChip(this.label, this.value, {required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        Text(value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
      ]),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.primary,
    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
    child: const Row(children: [
      _HCell('Mo.',    1),
      _HCell('Date',   2),
      _HCell('Pmt',    2),
      _HCell('Princ.', 2),
      _HCell('Int.',   2),
      _HCell('Bal.',   2),
    ]),
  );
}

class _HCell extends StatelessWidget {
  final String text;
  final int    flex;
  const _HCell(this.text, this.flex);

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: const TextStyle(
        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
      textAlign: TextAlign.right),
  );
}

class _Cell extends StatelessWidget {
  final String text;
  final int    flex;
  const _Cell(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: const TextStyle(fontSize: 11),
      textAlign: TextAlign.right),
  );
}

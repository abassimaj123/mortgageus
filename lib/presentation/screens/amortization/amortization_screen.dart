import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/amortization_entry.dart';
import '../../providers/mortgage_providers.dart';

// ── SharedPreferences key ─────────────────────────────────────────────────────
const _kViewModeKey = 'amort_view_yearly';

// ── Yearly group model ────────────────────────────────────────────────────────
class _YearGroup {
  final int    yearIndex;   // 1-based (Year 1, Year 2 …)
  final int    calendarYear;
  final List<AmortizationEntry> months;
  final double yearlyInterest;
  final double yearlyPrincipal;
  final double endBalance;
  final bool   hasPmiDrop;
  final bool   isHalfway;
  final bool   isLastYear;
  final bool   isCurrentYear;
  final double pctPaid;     // % of original loan paid at end of year

  const _YearGroup({
    required this.yearIndex,
    required this.calendarYear,
    required this.months,
    required this.yearlyInterest,
    required this.yearlyPrincipal,
    required this.endBalance,
    required this.hasPmiDrop,
    required this.isHalfway,
    required this.isLastYear,
    required this.isCurrentYear,
    required this.pctPaid,
  });
}

List<_YearGroup> _buildYearGroups(
  List<AmortizationEntry> schedule,
  double loanAmount,
) {
  final groups   = <_YearGroup>[];
  final now      = DateTime.now();
  final halfPaid = loanAmount / 2;
  bool  halfFlagged = false;

  for (int y = 0; y < (schedule.length / 12).ceil(); y++) {
    final start  = y * 12;
    final end    = (start + 12).clamp(0, schedule.length);
    final months = schedule.sublist(start, end);

    final interest  = months.fold<double>(0, (s, e) => s + e.interest);
    final principal = months.fold<double>(0, (s, e) => s + e.principal);
    final endBal    = months.last.balance;
    final calYear   = months.first.date.year;
    final paid      = loanAmount - endBal;
    final pct       = (paid / loanAmount * 100).clamp(0, 100);

    final hasPmiDrop = months.any((e) => e.pmiDropped);
    final isLast     = y == (schedule.length / 12).ceil() - 1;

    bool isHalf = false;
    if (!halfFlagged && paid >= halfPaid) {
      isHalf = true;
      halfFlagged = true;
    }

    groups.add(_YearGroup(
      yearIndex:    y + 1,
      calendarYear: calYear,
      months:       months,
      yearlyInterest:  interest,
      yearlyPrincipal: principal,
      endBalance:   endBal,
      hasPmiDrop:   hasPmiDrop,
      isHalfway:    isHalf,
      isLastYear:   isLast,
      isCurrentYear: calYear == now.year,
      pctPaid:      pct.toDouble(),
    ));
  }
  return groups;
}

// ── Screen ────────────────────────────────────────────────────────────────────
class AmortizationScreen extends ConsumerStatefulWidget {
  const AmortizationScreen({super.key});

  @override
  ConsumerState<AmortizationScreen> createState() => _AmortizationScreenState();
}

class _AmortizationScreenState extends ConsumerState<AmortizationScreen> {
  bool _yearlyView = true;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _yearlyView = prefs.getBool(_kViewModeKey) ?? true);
    }
  }

  Future<void> _setViewMode(bool yearly) async {
    setState(() => _yearlyView = yearly);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kViewModeKey, yearly);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(mortgageResultProvider);
    if (result == null) {
      return const Scaffold(
        body: Center(child: Text('Enter loan details in Calculator tab')));
    }

    final schedule = result.schedule;
    final fmt      = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
    final fmtDate  = DateFormat('MMM yyyy');
    final years    = _buildYearGroups(schedule, result.loanAmount);

    return Scaffold(
      appBar: AppBar(title: const Text('Amortization Schedule')),
      body: CustomScrollView(slivers: [

        // ── Summary card ───────────────────────────────────────────────────
        SliverToBoxAdapter(child: _SummaryCard(result: result, fmt: fmt, fmtDate: fmtDate)),

        // ── Pie chart ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    height: 180,
                    child: PieChart(PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: result.loanAmount,
                          title: 'Principal\n${fmt.format(result.loanAmount)}',
                          color: AppTheme.primary, radius: 70,
                          titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                        PieChartSectionData(
                          value: result.totalInterest,
                          title: 'Interest\n${fmt.format(result.totalInterest)}',
                          color: AppTheme.secondary, radius: 70,
                          titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                      ],
                      centerSpaceRadius: 0,
                    )),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Legend(color: AppTheme.primary,   label: 'Principal'),
                    const SizedBox(width: 24),
                    _Legend(color: AppTheme.secondary, label: 'Interest'),
                  ]),
                ]),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // ── View toggle ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Semantics(
              label: 'View mode toggle',
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true,  label: Text('Yearly View'),
                    icon: Icon(Icons.calendar_today)),
                  ButtonSegment(value: false, label: Text('Monthly View'),
                    icon: Icon(Icons.view_list)),
                ],
                selected: {_yearlyView},
                onSelectionChanged: (s) => _setViewMode(s.first),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // ── Content: yearly or monthly ─────────────────────────────────────
        if (_yearlyView)
          _YearlyList(years: years, fmt: fmt)
        else ...[
          SliverToBoxAdapter(child: _MonthlyHeader()),
          _MonthlyList(schedule: schedule, fmt: fmt),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final dynamic result;
  final NumberFormat fmt;
  final DateFormat   fmtDate;

  const _SummaryCard({required this.result, required this.fmt, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: AppTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Loan Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _SummaryRow('Loan amount',      fmt.format(result.loanAmount)),
            _SummaryRow('Payoff date',      fmtDate.format(result.payoffDate)),
            _SummaryRow('Total interest',   fmt.format(result.totalInterest)),
            _SummaryRow('Total payments',   fmt.format(result.totalCost)),
            if (result.pmiDropMonth != null)
              _SummaryRow('PMI removed',    'Month ${result.pmiDropMonth}'),
          ]),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      Text(value,  style: const TextStyle(color: Colors.white,   fontSize: 13,
        fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Yearly accordion list ─────────────────────────────────────────────────────
class _YearlyList extends StatelessWidget {
  final List<_YearGroup> years;
  final NumberFormat     fmt;
  const _YearlyList({required this.years, required this.fmt});

  @override
  Widget build(BuildContext context) => SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, i) => _YearTile(group: years[i], fmt: fmt),
      childCount: years.length,
    ),
  );
}

class _YearTile extends StatelessWidget {
  final _YearGroup   group;
  final NumberFormat fmt;
  const _YearTile({required this.group, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrentYear = group.isCurrentYear;

    // Build badge list
    final badges = <Widget>[];
    if (group.hasPmiDrop)  badges.add(_Badge('PMI removed', Colors.green));
    if (group.isHalfway)   badges.add(_Badge('Halfway',     Colors.blue));
    if (group.isLastYear)  badges.add(_Badge('Paid off',    AppTheme.secondary));

    return Semantics(
      label: 'Year ${group.yearIndex} ${group.calendarYear}. '
             'Balance ${fmt.format(group.endBalance)}. '
             '${group.pctPaid.toStringAsFixed(0)}% paid.',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isCurrentYear
              ? AppTheme.secondary.withValues(alpha: 0.08)
              : null,
          border: isCurrentYear
              ? Border.all(color: AppTheme.secondary, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          key: PageStorageKey('year_${group.yearIndex}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          leading: isCurrentYear
              ? const Icon(Icons.star, color: AppTheme.secondary, size: 18)
              : null,
          title: Row(children: [
            Expanded(
              child: Text('Year ${group.yearIndex}  (${group.calendarYear})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCurrentYear ? AppTheme.primary : null)),
            ),
            if (badges.isNotEmpty)
              Wrap(spacing: 4, children: badges),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 4),
            Text(
              'Balance: ${fmt.format(group.endBalance)}  •  '
              'Interest: ${fmt.format(group.yearlyInterest)}  •  '
              'Principal: ${fmt.format(group.yearlyPrincipal)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: group.pctPaid / 100,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  group.pctPaid > 78 ? Colors.green : AppTheme.primary),
              ),
            ),
            const SizedBox(height: 2),
            Text('${group.pctPaid.toStringAsFixed(1)}% paid',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
          ]),
          // Lazy sub-months (only built when expanded)
          children: [
            _MonthSubTable(months: group.months, fmt: fmt),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(label,
      style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
  );
}

// ── Sub-month table inside ExpansionTile ──────────────────────────────────────
class _MonthSubTable extends StatelessWidget {
  final List<AmortizationEntry> months;
  final NumberFormat            fmt;
  const _MonthSubTable({required this.months, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final hasPmi = months.any((e) => e.pmiAmount > 0 || e.pmiDropped);
    return Column(children: [
      // Sub-header
      Container(
        color: AppTheme.primary.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          _HCell('Mo.',    1),
          _HCell('Date',   2),
          _HCell('Pmt',    2),
          _HCell('Int.',   2),
          _HCell('Princ.', 2),
          _HCell('Bal.',   2),
          if (hasPmi) _HCell('PMI', 2),
        ]),
      ),
      // Month rows
      ...months.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final bg = e.pmiDropped
            ? Colors.green.shade50
            : i % 2 == 0 ? Colors.grey.shade50 : Colors.white;

        return Semantics(
          label: 'Month ${e.month}, balance ${fmt.format(e.balance)}',
          child: Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              _Cell('${e.month}',                               flex: 1),
              _Cell('${e.date.month}/${e.date.year}',           flex: 2),
              _Cell(fmt.format(e.payment),                      flex: 2),
              _Cell(fmt.format(e.interest),                     flex: 2),
              _Cell(fmt.format(e.principal),                    flex: 2),
              _Cell(fmt.format(e.balance),                      flex: 2),
              if (hasPmi)
                _Cell(e.pmiDropped ? 'OFF' :
                      e.pmiAmount > 0 ? fmt.format(e.pmiAmount) : '-', flex: 2),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── Monthly flat list ─────────────────────────────────────────────────────────
class _MonthlyHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(
      color: AppTheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: const Row(children: [
        _HCell('Mo.',    1),
        _HCell('Date',   2),
        _HCell('Pmt',    2),
        _HCell('Princ.', 2),
        _HCell('Int.',   2),
        _HCell('Bal.',   2),
      ]),
    ),
  );
}

class _MonthlyList extends StatelessWidget {
  final List<AmortizationEntry> schedule;
  final NumberFormat            fmt;
  const _MonthlyList({required this.schedule, required this.fmt});

  @override
  Widget build(BuildContext context) => SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, i) {
        final e  = schedule[i];
        final bg = e.pmiDropped
            ? Colors.orange.shade50
            : i % 2 == 0 ? Colors.grey.shade50 : Colors.white;
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Row(children: [
            _Cell('${e.month}',                flex: 1),
            _Cell('${e.date.month}/${e.date.year}', flex: 2),
            _Cell(fmt.format(e.payment),       flex: 2),
            _Cell(fmt.format(e.principal),     flex: 2),
            _Cell(fmt.format(e.interest),      flex: 2),
            _Cell(fmt.format(e.balance),       flex: 2),
          ]),
        );
      },
      childCount: schedule.length,
    ),
  );
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _Legend extends StatelessWidget {
  final Color color; final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 13, height: 13,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 12)),
  ]);
}

class _HCell extends StatelessWidget {
  final String text; final int flex;
  const _HCell(this.text, this.flex);
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: const TextStyle(
        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
      textAlign: TextAlign.right),
  );
}

class _Cell extends StatelessWidget {
  final String text; final int flex;
  const _Cell(this.text, {required this.flex});
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: const TextStyle(fontSize: 10),
      textAlign: TextAlign.right),
  );
}

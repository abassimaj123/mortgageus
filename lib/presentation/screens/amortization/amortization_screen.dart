import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../domain/models/amortization_entry.dart';
import '../../providers/mortgage_providers.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../main.dart' show isSpanishNotifier;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';

const _kFreeMonthLimit = 24; // 2 years free, full schedule = premium

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
    final result     = ref.watch(mortgageResultProvider);
    final inputState = ref.watch(mortgageInputProvider);

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();

        if (result == null) {
          return Scaffold(
            body: Center(child: Text(s.enterLoan)));
        }

        final schedule = result.schedule;
        final fmt      = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
        final fmtDate  = DateFormat('MMM yyyy');
        final years    = _buildYearGroups(schedule, result.loanAmount);

        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: CustomScrollView(slivers: [

            // ── Summary card ───────────────────────────────────────────────────
            SliverToBoxAdapter(child: _SummaryCard(result: result, inputState: inputState, fmt: fmt, fmtDate: fmtDate, s: s)),

            // ── Pie chart ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text(s.lifeBreakdown,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: PieChart(PieChartData(
                          sections: [
                            PieChartSectionData(
                              value: result.loanAmount,
                              title: '${s.principal}\n${fmt.format(result.loanAmount)}',
                              color: AppTheme.primary, radius: 70,
                              titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                            PieChartSectionData(
                              value: result.totalInterest,
                              title: '${s.interest}\n${fmt.format(result.totalInterest)}',
                              color: AppTheme.secondary, radius: 70,
                              titleStyle: const TextStyle(color: Colors.white, fontSize: 10)),
                          ],
                          centerSpaceRadius: 0,
                        )),
                      ),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _Legend(color: AppTheme.primary,   label: s.principal),
                        const SizedBox(width: 24),
                        _Legend(color: AppTheme.secondary, label: s.interest),
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
                    segments: [
                      ButtonSegment(value: true,  label: Text(s.yearlyView),
                        icon: const Icon(Icons.calendar_today)),
                      ButtonSegment(value: false, label: Text(s.monthlyView),
                        icon: const Icon(Icons.view_list)),
                    ],
                    selected: {_yearlyView},
                    onSelectionChanged: (sel) => _setViewMode(sel.first),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── Content: yearly or monthly ─────────────────────────────────────
            if (_yearlyView)
              _YearlyList(years: years, fmt: fmt, s: s, isPremium: freemiumService.isPremium)
            else ...[
              SliverToBoxAdapter(child: _MonthlyHeader(s: s)),
              _MonthlyList(schedule: schedule, fmt: fmt, s: s, isPremium: freemiumService.isPremium),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ]),
              ),
              const AdFooter(),
            ],
          ),
        );
      },
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final dynamic result;
  final dynamic inputState;
  final NumberFormat fmt;
  final DateFormat   fmtDate;
  final dynamic      s;

  const _SummaryCard({required this.result, required this.inputState, required this.fmt, required this.fmtDate, required this.s});

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
            Text(s.loanSummary,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Show home price + down payment for clarity
            _SummaryRow(s.homePrice,
              '${fmt.format(inputState.homePrice)}  (${inputState.downPaymentPct.toStringAsFixed(0)}% down)'),
            _SummaryRow(s.loanAmount,    fmt.format(result.loanAmount)),
            _SummaryRow(s.payoffDate,    fmtDate.format(result.payoffDate)),
            _SummaryRow(s.totalInterest, fmt.format(result.totalInterest)),
            _SummaryRow(s.totalPayments, fmt.format(result.totalCost)),
            if (result.pmiDropMonth != null)
              _SummaryRow(s.pmiRemoved,  'Month ${result.pmiDropMonth}'),
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
  final dynamic          s;
  final bool             isPremium;
  const _YearlyList({required this.years, required this.fmt, required this.s, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    // Free: show first 2 years (= 24 months) + lock banner
    final freeYearLimit = (_kFreeMonthLimit / 12).floor(); // 2
    final visibleYears  = isPremium ? years : years.take(freeYearLimit).toList();
    final locked        = !isPremium && years.length > freeYearLimit;
    final isEs          = isSpanishNotifier.value;
    final totalYears    = years.length;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i < visibleYears.length) {
            return _YearTile(group: visibleYears[i], fmt: fmt, s: s);
          }
          // Lock banner (only appended when locked)
          return _AmortLockBanner(
            isEs: isEs,
            lockedYears: totalYears - freeYearLimit,
            lockedMonths: (totalYears - freeYearLimit) * 12,
          );
        },
        childCount: visibleYears.length + (locked ? 1 : 0),
      ),
    );
  }
}

class _YearTile extends StatelessWidget {
  final _YearGroup   group;
  final NumberFormat fmt;
  final dynamic      s;
  const _YearTile({required this.group, required this.fmt, required this.s});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrentYear = group.isCurrentYear;

    // Build badge list
    final badges = <Widget>[];
    if (group.hasPmiDrop)  badges.add(_Badge(s.pmiRemoved, Colors.green));
    if (group.isHalfway)   badges.add(_Badge(s.halfway,    Colors.blue));
    if (group.isLastYear)  badges.add(_Badge(s.paidOff,    AppTheme.secondary));

    return Semantics(
      label: '${s.year} ${group.yearIndex} ${group.calendarYear}. '
             '${s.balance}: ${fmt.format(group.endBalance)}. '
             '${group.pctPaid.toStringAsFixed(0)}% ${s.paid}.',
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
              child: Text('${s.year} ${group.yearIndex}  (${group.calendarYear})',
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
              '${s.balance}: ${fmt.format(group.endBalance)}  •  '
              '${s.interest}: ${fmt.format(group.yearlyInterest)}  •  '
              '${s.principal}: ${fmt.format(group.yearlyPrincipal)}',
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
            Text('${group.pctPaid.toStringAsFixed(1)}% ${s.paid}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
          ]),
          // Lazy sub-months (only built when expanded)
          children: [
            _MonthSubTable(months: group.months, fmt: fmt, s: s),
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
  final dynamic                 s;
  const _MonthSubTable({required this.months, required this.fmt, required this.s});

  @override
  Widget build(BuildContext context) {
    final hasPmi = months.any((e) => e.pmiAmount > 0 || e.pmiDropped);
    return Column(children: [
      // Sub-header
      Container(
        color: AppTheme.primary.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          _HCell(s.colMo,    1),
          _HCell(s.colDate,  2),
          _HCell(s.colPmt,   2),
          _HCell(s.colInt,   2),
          _HCell(s.colPrinc, 2),
          _HCell(s.colBal,   2),
          if (hasPmi) _HCell(s.pmi, 2),
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
                _Cell(e.pmiDropped ? s.off :
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
  final dynamic s;
  const _MonthlyHeader({required this.s});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(
      color: AppTheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(children: [
        _HCell(s.colMo,    1),
        _HCell(s.colDate,  2),
        _HCell(s.colPmt,   2),
        _HCell(s.colPrinc, 2),
        _HCell(s.colInt,   2),
        _HCell(s.colBal,   2),
      ]),
    ),
  );
}

class _MonthlyList extends StatelessWidget {
  final List<AmortizationEntry> schedule;
  final NumberFormat            fmt;
  final dynamic                 s;
  final bool                    isPremium;
  const _MonthlyList({required this.schedule, required this.fmt, required this.s, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final visible = isPremium ? schedule : schedule.take(_kFreeMonthLimit).toList();
    final locked  = !isPremium && schedule.length > _kFreeMonthLimit;
    final isEs    = isSpanishNotifier.value;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i < visible.length) {
            final e  = visible[i];
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
          }
          return _AmortLockBanner(
            isEs: isEs,
            lockedYears: ((schedule.length - _kFreeMonthLimit) / 12).ceil(),
            lockedMonths: schedule.length - _kFreeMonthLimit,
          );
        },
        childCount: visible.length + (locked ? 1 : 0),
      ),
    );
  }
}

// ── Premium lock banner ───────────────────────────────────────────────────────
class _AmortLockBanner extends StatelessWidget {
  final bool isEs;
  final int  lockedYears;
  final int  lockedMonths;
  const _AmortLockBanner({required this.isEs, required this.lockedYears, required this.lockedMonths});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.08), AppTheme.primary.withValues(alpha: 0.02)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(children: [
        const Icon(Icons.lock_outline, color: AppTheme.secondary, size: 36),
        const SizedBox(height: 12),
        Text(
          isEs ? 'Tabla completa bloqueada' : 'Full schedule locked',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        const SizedBox(height: 6),
        Text(
          isEs
              ? '+$lockedYears años · +$lockedMonths meses restantes'
              : '+$lockedYears years · +$lockedMonths months remaining',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => IAPService.instance.buy(),
            icon: const Icon(Icons.workspace_premium, size: 18),
            label: Text(
              isEs ? 'Desbloquear Premium — \$4.99' : 'Unlock Premium — \$4.99',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isEs ? 'Acceso único · Sin suscripción' : 'One-time purchase · No subscription',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ]),
    );
  }
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

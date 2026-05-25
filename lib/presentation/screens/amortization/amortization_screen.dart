import 'dart:ui' show FontFeature;
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
import '../../../domain/models/mortgage_result.dart';
import '../../../main.dart' show isSpanishNotifier, tabSwitchNotifier;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'package:calcwise_core/calcwise_core.dart';

const _kFreeMonthLimit = 24; // 2 years free, full schedule = premium

// ── SharedPreferences key ─────────────────────────────────────────────────────
const _kViewModeKey = 'amort_view_yearly';

// ── Yearly group model ────────────────────────────────────────────────────────
class _YearGroup {
  final int yearIndex; // 1-based (Year 1, Year 2 …)
  final int calendarYear;
  final List<AmortizationEntry> months;
  final double yearlyInterest;
  final double yearlyPrincipal;
  final double endBalance;
  final bool hasPmiDrop;
  final bool isHalfway;
  final bool isLastYear;
  final bool isCurrentYear;
  final double pctPaid; // % of original loan paid at end of year

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
  final groups = <_YearGroup>[];
  final now = DateTime.now();
  final halfPaid = loanAmount / 2;
  bool halfFlagged = false;

  for (int y = 0; y < (schedule.length / 12).ceil(); y++) {
    final start = y * 12;
    final end = (start + 12).clamp(0, schedule.length);
    final months = schedule.sublist(start, end);

    final interest = months.fold<double>(0, (s, e) => s + e.interest);
    final principal = months.fold<double>(0, (s, e) => s + e.principal);
    final endBal = months.last.balance;
    final calYear = months.first.date.year;
    final paid = loanAmount - endBal;
    final pct = (paid / loanAmount * 100).clamp(0, 100);

    final hasPmiDrop = months.any((e) => e.pmiDropped);
    final isLast = y == (schedule.length / 12).ceil() - 1;

    bool isHalf = false;
    if (!halfFlagged && paid >= halfPaid) {
      isHalf = true;
      halfFlagged = true;
    }

    groups.add(_YearGroup(
      yearIndex: y + 1,
      calendarYear: calYear,
      months: months,
      yearlyInterest: interest,
      yearlyPrincipal: principal,
      endBalance: endBal,
      hasPmiDrop: hasPmiDrop,
      isHalfway: isHalf,
      isLastYear: isLast,
      isCurrentYear: calYear == now.year,
      pctPaid: pct.toDouble(),
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

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadPref();
    freemiumService.isRewardedNotifier.addListener(_rebuild);
    freemiumService.isPremiumNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    freemiumService.isRewardedNotifier.removeListener(_rebuild);
    freemiumService.isPremiumNotifier.removeListener(_rebuild);
    super.dispose();
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
    final inputState = ref.watch(mortgageInputProvider);

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();

        if (result == null) {
          return Scaffold(
            bottomNavigationBar: const CalcwiseAdFooter(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.table_rows_rounded,
                          size: 40, color: AppTheme.primary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      isEs
                          ? 'Tu tabla aparecerá aquí'
                          : 'Your schedule will appear here',
                      style: const TextStyle(
                          fontSize: AppTextSize.subtitle,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      isEs
                          ? 'Ingresa los datos de tu préstamo en la calculadora para ver el desglose mes a mes.'
                          : 'Enter your loan details in the calculator to see your month-by-month breakdown.',
                      style: const TextStyle(
                          fontSize: AppTextSize.body,
                          color: AppTheme.labelGray),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Semantics(
                        label:
                            isEs ? 'Ir a la calculadora' : 'Go to Calculator',
                        button: true,
                        child: GestureDetector(
                          onTap: () => tabSwitchNotifier.value = 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xxl,
                                vertical: AppSpacing.mdPlus),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.mdPlus),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.calculate_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                  isEs
                                      ? 'Ir a la calculadora'
                                      : 'Go to Calculator',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          );
        }

        final schedule = result.schedule;
        final fmt = NumberFormat.currency(
            locale: 'en_US', symbol: '\$', decimalDigits: 0);
        final fmtDate = DateFormat('MMM yyyy');
        final years = _buildYearGroups(schedule, result.loanAmount);

        return Scaffold(
          bottomNavigationBar: const CalcwiseAdFooter(),
          body: CustomScrollView(slivers: [
            // ── Summary card ───────────────────────────────────────────────────
            SliverToBoxAdapter(
                child: _SummaryCard(
                    result: result,
                    inputState: inputState,
                    fmt: fmt,
                    fmtDate: fmtDate,
                    s: s)),

            // ── Donut chart ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(children: [
                      Text(s.lifeBreakdown,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.md),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isSmallScreen = constraints.maxWidth < 400;
                          final chartSize = isSmallScreen
                              ? (constraints.maxWidth - 32) * 0.7
                              : (constraints.maxWidth - 32) * 0.4;
                          // Responsive radius scaling: scales with chart size
                          final responsiveCenter = chartSize * 0.35;
                          final responsiveSection = chartSize * 0.15;
                          final _total =
                              result.loanAmount + result.totalInterest;
                          final _principalPct = _total > 0
                              ? (result.loanAmount / _total * 100).round()
                              : 0;
                          final _interestPct = _total > 0
                              ? (result.totalInterest / _total * 100).round()
                              : 0;
                          final _chartLabel = isEs
                              ? 'Desglose total: ${fmt.format(result.loanAmount)} capital ($_principalPct%), '
                                  '${fmt.format(result.totalInterest)} interés ($_interestPct%)'
                              : 'Lifetime breakdown: ${fmt.format(result.loanAmount)} principal ($_principalPct%), '
                                  '${fmt.format(result.totalInterest)} interest ($_interestPct%)';
                          return Flex(
                            direction:
                                isSmallScreen ? Axis.vertical : Axis.horizontal,
                            children: [
                              Semantics(
                                label: _chartLabel,
                                excludeSemantics: true,
                                child: SizedBox(
                                  height: chartSize,
                                  width: chartSize,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      PieChart(
                                        PieChartData(
                                          sectionsSpace: 2,
                                          centerSpaceRadius: responsiveCenter,
                                          pieTouchData: PieTouchData(
                                            enabled: true,
                                            touchCallback: (event, response) {},
                                          ),
                                          sections: [
                                            PieChartSectionData(
                                              value: result.loanAmount,
                                              color: AppTheme.primary,
                                              radius: responsiveSection,
                                              showTitle: false,
                                            ),
                                            PieChartSectionData(
                                              value: result.totalInterest,
                                              color: AppTheme.secondary,
                                              radius: responsiveSection,
                                              showTitle: false,
                                            ),
                                          ],
                                        ),
                                        swapAnimationDuration:
                                            const Duration(milliseconds: 500),
                                      ),
                                      // Center overlay — interest %
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${result.loanAmount + result.totalInterest > 0 ? (result.totalInterest / (result.loanAmount + result.totalInterest) * 100).round() : 0}%',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: AppTextSize.title,
                                              color: AppTheme.secondary,
                                            ),
                                          ),
                                          Text(
                                            isEs ? 'interés' : 'interest',
                                            style: const TextStyle(
                                              fontSize: AppTextSize.xs,
                                              color: AppTheme.labelGray,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ), // Semantics
                              if (isSmallScreen)
                                const SizedBox(height: AppSpacing.lg)
                              else
                                const SizedBox(width: AppSpacing.lg),
                              if (isSmallScreen)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _LegendRow(
                                      color: AppTheme.primary,
                                      label: s.principal,
                                      value: fmt.format(result.loanAmount),
                                    ),
                                    const SizedBox(height: AppSpacing.smPlus),
                                    _LegendRow(
                                      color: AppTheme.secondary,
                                      label: s.interest,
                                      value: fmt.format(result.totalInterest),
                                      valueColor: AppTheme.secondary,
                                    ),
                                    const SizedBox(height: AppSpacing.smPlus),
                                    Container(
                                        height: 1,
                                        color: AppTheme.labelGray,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 0)),
                                    const SizedBox(height: AppSpacing.sm),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          isEs ? 'Total' : 'Total',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: AppTextSize.md),
                                        ),
                                        Text(
                                          fmt.format(result.loanAmount +
                                              result.totalInterest),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: AppTextSize.md),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              else
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _LegendRow(
                                        color: AppTheme.primary,
                                        label: s.principal,
                                        value: fmt.format(result.loanAmount),
                                      ),
                                      const SizedBox(height: AppSpacing.smPlus),
                                      _LegendRow(
                                        color: AppTheme.secondary,
                                        label: s.interest,
                                        value: fmt.format(result.totalInterest),
                                        valueColor: AppTheme.secondary,
                                      ),
                                      const SizedBox(height: AppSpacing.smPlus),
                                      Container(
                                          height: 1,
                                          color: AppTheme.labelGray,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 0)),
                                      const SizedBox(height: AppSpacing.sm),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            isEs ? 'Total' : 'Total',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: AppTextSize.md),
                                          ),
                                          Text(
                                            fmt.format(result.loanAmount +
                                                result.totalInterest),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: AppTextSize.md),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // ── View toggle ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Semantics(
                  label: 'View mode toggle',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.5)),
                    ),
                    child: Row(children: [
                      Expanded(
                          child: Semantics(
                              label: s.yearlyView,
                              button: true,
                              selected: _yearlyView,
                              child: GestureDetector(
                                onTap: () => _setViewMode(true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.smPlus),
                                  decoration: BoxDecoration(
                                    color: _yearlyView
                                        ? AppTheme.primary
                                        : Colors.transparent,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(7),
                                      bottomLeft: Radius.circular(7),
                                    ),
                                  ),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.calendar_today,
                                            size: 16,
                                            color: _yearlyView
                                                ? Colors.white
                                                : AppTheme.primary),
                                        const SizedBox(width: AppRadius.sm),
                                        Text(s.yearlyView,
                                            style: TextStyle(
                                                color: _yearlyView
                                                    ? Colors.white
                                                    : AppTheme.primary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: AppTextSize.md)),
                                      ]),
                                ),
                              ))),
                      Container(
                          width: 1,
                          height: 38,
                          color: AppTheme.primary.withValues(alpha: 0.5)),
                      Expanded(
                          child: Semantics(
                              label: s.monthlyView,
                              button: true,
                              selected: !_yearlyView,
                              child: GestureDetector(
                                onTap: () => _setViewMode(false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.smPlus),
                                  decoration: BoxDecoration(
                                    color: !_yearlyView
                                        ? AppTheme.primary
                                        : Colors.transparent,
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(7),
                                      bottomRight: Radius.circular(7),
                                    ),
                                  ),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.view_list,
                                            size: 16,
                                            color: !_yearlyView
                                                ? Colors.white
                                                : AppTheme.primary),
                                        const SizedBox(width: AppRadius.sm),
                                        Text(s.monthlyView,
                                            style: TextStyle(
                                                color: !_yearlyView
                                                    ? Colors.white
                                                    : AppTheme.primary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: AppTextSize.md)),
                                      ]),
                                ),
                              ))),
                    ]),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // ── Content: yearly or monthly ─────────────────────────────────────
            if (_yearlyView)
              _YearlyList(
                  years: years,
                  fmt: fmt,
                  s: s,
                  isPremium: freemiumService.hasFullAccess)
            else ...[
              SliverToBoxAdapter(child: _MonthlyHeader(s: s)),
              _MonthlyList(
                  schedule: schedule,
                  fmt: fmt,
                  s: s,
                  isPremium: freemiumService.hasFullAccess),
            ],

            const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.listBottomInset)),
          ]),
        );
      },
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final MortgageResult result;
  final MortgageInputState inputState;
  final NumberFormat fmt;
  final DateFormat fmtDate;
  final AppStrings s;

  const _SummaryCard(
      {required this.result,
      required this.inputState,
      required this.fmt,
      required this.fmtDate,
      required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.loanSummary,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.md),
        // Show home price + down payment for clarity
        _SummaryRow(s.homePrice,
            '${fmt.format(inputState.homePrice)}  (${inputState.downPaymentPct.toStringAsFixed(0)}% down)'),
        _SummaryRow(s.loanAmount, fmt.format(result.loanAmount)),
        _SummaryRow(
            s.payoffDate, fmtDate.format(result.payoffDate as DateTime)),
        _SummaryRow(s.totalInterest, fmt.format(result.totalInterest)),
        _SummaryRow(s.totalPayments, fmt.format(result.totalCost)),
        if (result.pmiDropMonth != null)
          _SummaryRow(s.pmiRemoved, 'Month ${result.pmiDropMonth}'),
      ]),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: AppTextSize.md)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTextSize.md,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// ── Yearly accordion list ─────────────────────────────────────────────────────
class _YearlyList extends StatelessWidget {
  final List<_YearGroup> years;
  final NumberFormat fmt;
  final AppStrings s;
  final bool isPremium;
  const _YearlyList(
      {required this.years,
      required this.fmt,
      required this.s,
      required this.isPremium});

  @override
  Widget build(BuildContext context) {
    // Free: show first 2 years (= 24 months) + lock banner
    final freeYearLimit = (_kFreeMonthLimit / 12).floor(); // 2
    final visibleYears = isPremium ? years : years.take(freeYearLimit).toList();
    final locked = !isPremium && years.length > freeYearLimit;
    final isEs = isSpanishNotifier.value;
    final totalYears = years.length;

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

class _YearTile extends StatefulWidget {
  final _YearGroup group;
  final NumberFormat fmt;
  final AppStrings s;
  const _YearTile({required this.group, required this.fmt, required this.s});
  @override
  State<_YearTile> createState() => _YearTileState();
}

class _YearTileState extends State<_YearTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final fmt = widget.fmt;
    final s = widget.s;
    final isCurrentYear = group.isCurrentYear;

    final badges = <Widget>[];
    if (group.hasPmiDrop)
      badges.add(_Badge(s.pmiRemoved, CalcwiseSemanticColors.successDeep));
    if (group.isHalfway)
      badges.add(_Badge(s.halfway, CalcwiseSemanticColors.infoIcon));
    if (group.isLastYear) badges.add(_Badge(s.paidOff, AppTheme.secondary));

    return Semantics(
      label: '${s.year} ${group.yearIndex} ${group.calendarYear}. '
          '${s.balance}: ${fmt.format(group.endBalance)}. '
          '${group.pctPaid.toStringAsFixed(0)}% ${s.paid}.',
      child: Container(
        margin:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
        decoration: BoxDecoration(
          color:
              isCurrentYear ? AppTheme.secondary.withValues(alpha: 0.08) : null,
          border: isCurrentYear
              ? Border.all(color: AppTheme.secondary, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(children: [
            // ── Header row (tappable) ──────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.smPlus),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (isCurrentYear) ...[
                          const Icon(Icons.star_rounded,
                              color: AppTheme.secondary, size: 18),
                          const SizedBox(width: AppRadius.sm),
                        ],
                        Expanded(
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                '${s.year} ${group.yearIndex}  (${group.calendarYear})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.body,
                                  color:
                                      isCurrentYear ? AppTheme.primary : null,
                                ),
                              ),
                            ),
                            if (badges.isNotEmpty)
                              Wrap(spacing: 4, children: badges),
                          ]),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: AppTheme.labelGray,
                          size: 20,
                        ),
                      ]),
                      const SizedBox(height: AppRadius.sm),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        _MetricChip(
                            label: s.balance,
                            value: fmt.format(group.endBalance),
                            color: AppTheme.primary),
                        _MetricChip(
                            label: s.interest,
                            value: fmt.format(group.yearlyInterest),
                            color: AppTheme.secondary),
                        _MetricChip(
                            label: s.principal,
                            value: fmt.format(group.yearlyPrincipal),
                            color: AppTheme.accentGood),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      // Custom progress bar — no Material LinearProgressIndicator
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                              begin: 0.0, end: group.pctPaid / 100),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          builder: (context, value, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            child: SizedBox(
                              height: 6,
                              width: constraints.maxWidth,
                              child: Stack(children: [
                                Container(
                                    color: AppTheme.labelGray
                                        .withValues(alpha: 0.15)),
                                Container(
                                  width: constraints.maxWidth * value,
                                  color: group.pctPaid > 78
                                      ? AppTheme.accentGood
                                      : AppTheme.primary,
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text('${group.pctPaid.toStringAsFixed(1)}% ${s.paid}',
                          style: const TextStyle(fontSize: AppTextSize.xs)),
                    ]),
              ),
            ),
            // ── Expanded sub-months ────────────────────────────────────────
            if (_expanded) _MonthSubTable(months: group.months, fmt: fmt, s: s),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: AppTextSize.xxs, color: color, fontWeight: FontWeight.bold)),
      );
}

// ── Sub-month table inside ExpansionTile ──────────────────────────────────────
class _MonthSubTable extends StatelessWidget {
  final List<AmortizationEntry> months;
  final NumberFormat fmt;
  final AppStrings s;
  const _MonthSubTable(
      {required this.months, required this.fmt, required this.s});

  @override
  Widget build(BuildContext context) {
    final hasPmi = months.any((e) => e.pmiAmount > 0 || e.pmiDropped);
    return Column(children: [
      // Sub-header
      Container(
        color: AppTheme.primary.withValues(alpha: 0.85),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        child: Row(children: [
          _HCell(s.colMo, 1),
          _HCell(s.colDate, 2),
          _HCell(s.colPmt, 2),
          _HCell(s.colInt, 2),
          _HCell(s.colPrinc, 2),
          _HCell(s.colBal, 2),
          if (hasPmi) _HCell(s.pmi, 2),
        ]),
      ),
      // Month rows
      ...months.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final bg = e.pmiDropped
            ? AppTheme.accentGood.withValues(alpha: 0.08)
            : i % 2 == 0
                ? Theme.of(context).colorScheme.surfaceContainerLow
                : Theme.of(context).colorScheme.surface;

        return Semantics(
          label: 'Month ${e.month}, balance ${fmt.format(e.balance)}',
          child: Container(
            color: bg,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 6),
            child: Row(children: [
              _Cell('${e.month}', flex: 1),
              _Cell('${e.date.month}/${e.date.year}', flex: 2),
              _Cell(fmt.format(e.payment), flex: 2),
              _Cell(fmt.format(e.interest), flex: 2),
              _Cell(fmt.format(e.principal), flex: 2),
              _Cell(fmt.format(e.balance), flex: 2),
              if (hasPmi)
                _Cell(
                    e.pmiDropped
                        ? s.off
                        : e.pmiAmount > 0
                            ? fmt.format(e.pmiAmount)
                            : '-',
                    flex: 2),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── Monthly flat list ─────────────────────────────────────────────────────────
class _MonthlyHeader extends StatelessWidget {
  final AppStrings s;
  const _MonthlyHeader({required this.s});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Container(
          color: AppTheme.primary,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.smPlus),
          child: Row(children: [
            _HCell(s.colMo, 1),
            _HCell(s.colDate, 2),
            _HCell(s.colPmt, 2),
            _HCell(s.colPrinc, 2),
            _HCell(s.colInt, 2),
            _HCell(s.colBal, 2),
          ]),
        ),
      );
}

class _MonthlyList extends StatelessWidget {
  final List<AmortizationEntry> schedule;
  final NumberFormat fmt;
  final AppStrings s;
  final bool isPremium;
  const _MonthlyList(
      {required this.schedule,
      required this.fmt,
      required this.s,
      required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final visible =
        isPremium ? schedule : schedule.take(_kFreeMonthLimit).toList();
    final locked = !isPremium && schedule.length > _kFreeMonthLimit;
    final isEs = isSpanishNotifier.value;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i < visible.length) {
            final e = visible[i];
            final bg = e.pmiDropped
                ? AppTheme.accentWarn.withValues(alpha: 0.08)
                : i % 2 == 0
                    ? Theme.of(context).colorScheme.surfaceContainerLow
                    : Theme.of(context).colorScheme.surface;
            return Container(
              color: bg,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: 7),
              child: Row(children: [
                _Cell('${e.month}', flex: 1),
                _Cell('${e.date.month}/${e.date.year}', flex: 2),
                _Cell(fmt.format(e.payment), flex: 2),
                _Cell(fmt.format(e.principal), flex: 2),
                _Cell(fmt.format(e.interest), flex: 2),
                _Cell(fmt.format(e.balance), flex: 2),
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
  final int lockedYears;
  final int lockedMonths;
  const _AmortLockBanner(
      {required this.isEs,
      required this.lockedYears,
      required this.lockedMonths});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 80),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.08),
            AppTheme.primary.withValues(alpha: 0.02)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl, vertical: AppSpacing.xxlPlus),
      child: Column(children: [
        const Icon(Icons.lock_outline, color: AppTheme.secondary, size: 36),
        const SizedBox(height: AppSpacing.md),
        Text(
          isEs ? 'Tabla completa bloqueada' : 'Full schedule locked',
          style: const TextStyle(
              fontSize: AppTextSize.bodyLg,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary),
        ),
        const SizedBox(height: AppRadius.sm),
        Text(
          isEs
              ? '+$lockedYears años · +$lockedMonths meses restantes'
              : '+$lockedYears years · +$lockedMonths months remaining',
          style: const TextStyle(
              fontSize: AppTextSize.md, color: AppTheme.labelGray),
        ),
        const SizedBox(height: AppSpacing.xl),
        GestureDetector(
          onTap: () => IAPService.instance.buy(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.mdPlus),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.workspace_premium,
                  size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isEs
                    ? 'Desbloquear Premium — \$4.99'
                    : 'Unlock Premium — \$4.99',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ]),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isEs
              ? 'Acceso único · Sin suscripción'
              : 'One-time purchase · No subscription',
          style: const TextStyle(
              fontSize: AppTextSize.xs, color: AppTheme.labelGray),
        ),
      ]),
    );
  }
}

// ── Metric chip (year tile subtitle) ─────────────────────────────────────────
class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: AppTextSize.xxs, color: color.withValues(alpha: 0.8))),
            Text(value,
                style: TextStyle(
                    fontSize: AppTextSize.xs,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      );
}

// ── Legend row (donut chart) ──────────────────────────────────────────────────
class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final Color? valueColor;
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: AppTextSize.sm, color: AppTheme.labelGray)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextSize.sm,
            color: valueColor,
          ),
        ),
      ]);
}

// ── Shared table cell widgets ─────────────────────────────────────────────────
class _HCell extends StatelessWidget {
  final String text;
  final int flex;
  const _HCell(this.text, this.flex);
  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.tableHeaderSize),
            textAlign: TextAlign.right),
      );
}

class _Cell extends StatelessWidget {
  final String text;
  final int flex;
  const _Cell(this.text, {required this.flex});
  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(text,
            style: const TextStyle(
                fontSize: AppTheme.tableBodySize,
                fontFeatures: [FontFeature.tabularFigures()]),
            textAlign: TextAlign.right),
      );
}

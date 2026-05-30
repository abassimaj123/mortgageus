import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../providers/mortgage_providers.dart';
import '../../../main.dart' show isSpanishNotifier, tabSwitchNotifier;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'history_detail_screen.dart';

// ── Item model for grouped display ───────────────────────────────────────────

class _HistoryItem {
  final Map<String, dynamic>? single;
  final List<Map<String, dynamic>>? comparison; // [r30, r15] or [r15, r30]
  final String? comparisonId;

  bool get isComparison => comparison != null;

  const _HistoryItem.single(Map<String, dynamic> row)
      : single = row,
        comparison = null,
        comparisonId = null;

  const _HistoryItem.pair(List<Map<String, dynamic>> rows, String cid)
      : single = null,
        comparison = rows,
        comparisonId = cid;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static final refreshNotifier = ValueNotifier<int>(0);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  List<_HistoryItem> _items = [];
  bool _firstLoad = true;

  // Compare mode
  bool _compareMode = false;
  final Set<int> _selectedIds = {}; // ids of selected single rows

  final _fmtDate = DateFormat('MMM d, yyyy – HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
    HistoryScreen.refreshNotifier.addListener(_silentRefresh);
  }

  @override
  void dispose() {
    HistoryScreen.refreshNotifier.removeListener(_silentRefresh);
    super.dispose();
  }

  List<_HistoryItem> _groupRows(List<Map<String, dynamic>> rows) {
    final items = <_HistoryItem>[];
    final seenCids = <String>{};

    for (final row in rows) {
      final cid = row['comparison_id'] as String?;
      if (cid != null && cid.isNotEmpty) {
        if (!seenCids.contains(cid)) {
          seenCids.add(cid);
          final pair = rows.where((r) => r['comparison_id'] == cid).toList()
            ..sort((a, b) => (b['term_years'] as int? ?? 30)
                .compareTo(a['term_years'] as int? ?? 30)); // 30yr first
          items.add(_HistoryItem.pair(pair, cid));
        }
      } else {
        items.add(_HistoryItem.single(row));
      }
    }
    return items;
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getHistory();
    if (mounted) {
      setState(() {
        _history = rows;
        _items = _groupRows(rows);
        _firstLoad = false;
      });
    }
  }

  Future<void> _silentRefresh() async {
    final rows = await DatabaseHelper.instance.getHistory();
    if (mounted) {
      setState(() {
        _history = rows;
        _items = _groupRows(rows);
      });
    }
  }

  // ── Delete helpers ────────────────────────────────────────────────────────

  Future<void> _delete(int id, BuildContext context) async {
    final isEs = isSpanishNotifier.value;
    final confirm = await _confirmDelete(context, isEs);
    if (confirm == true) {
      await DatabaseHelper.instance.deleteHistory(id);
      _load();
    }
  }

  Future<void> _deleteComparison(
      String comparisonId, BuildContext context) async {
    final isEs = isSpanishNotifier.value;
    final confirm = await _confirmDelete(context, isEs, isComparison: true);
    if (confirm == true) {
      await DatabaseHelper.instance.deleteByComparisonId(comparisonId);
      _load();
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, bool isEs,
      {bool isComparison = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEs
            ? (isComparison ? '¿Eliminar comparación?' : '¿Eliminar entrada?')
            : (isComparison ? 'Delete comparison?' : 'Delete entry?')),
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
  }

  Future<void> _clearAll() async {
    await DatabaseHelper.instance.clearHistory();
    _load();
  }

  String _dateGroup(DateTime d, bool isEs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entry = DateTime(d.year, d.month, d.day);
    final diff = today.difference(entry).inDays;
    if (diff <= 0) return isEs ? 'Hoy' : 'Today';
    if (diff < 7) return isEs ? 'Esta semana' : 'This week';
    if (diff < 30) return isEs ? 'Este mes' : 'This month';
    return isEs ? 'Anterior' : 'Older';
  }

  DateTime _itemDate(_HistoryItem it) {
    final row = it.isComparison ? it.comparison!.first : it.single!;
    return DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now();
  }

  String _shortK(double v) {
    if (v >= 1000000)
      return '\$${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}k';
    return '\$${v.toStringAsFixed(0)}';
  }

  // ── LoanType helper ───────────────────────────────────────────────────────

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

  // ── PDF export ────────────────────────────────────────────────────────────

  Future<void> _exportPdf(
      BuildContext context, Map<String, dynamic> row) async {
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
            isEs: isSpanishNotifier.value);
      }
    } catch (e) {
      if (context.mounted) {
        final bool isEs = isSpanishNotifier.value;
        final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.exportFailed}: $e')),
        );
      }
    }
  }

  // ── Detail sheet (comparison only — singles go to HistoryDetailScreen) ──────

  void _showComparisonDetail(BuildContext context,
      List<Map<String, dynamic>> pair, String cid, bool isEs) {
    // pair is [r30, r15] — sorted by term_years DESC when built
    final r30row = pair.firstWhere((r) => (r['term_years'] as int? ?? 30) == 30,
        orElse: () => pair.first);
    final r15row = pair.firstWhere((r) => (r['term_years'] as int? ?? 30) == 15,
        orElse: () => pair.last);

    final homePrice = (r30row['home_price'] as num?)?.toDouble() ?? 0.0;
    final annualRate = (r30row['annual_rate'] as num?)?.toDouble() ?? 0.0;
    final loanType = r30row['loan_type'] as String? ?? 'Conventional';
    final createdAt =
        DateTime.tryParse(r30row['created_at'] as String? ?? '') ??
            DateTime.now();

    final m30 = (r30row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final m15 = (r15row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final i30 = (r30row['total_interest'] as num?)?.toDouble() ?? 0.0;
    final i15 = (r15row['total_interest'] as num?)?.toDouble() ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: ListView(
            controller: controller,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Title
              Row(children: [
                const Icon(Icons.compare_arrows,
                    color: AppTheme.primary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isEs ? 'Comparación guardada' : 'Saved comparison',
                    style: const TextStyle(
                        fontSize: AppTextSize.subtitle,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${AmountFormatter.ui(homePrice, 'USD')} · $loanType · ${annualRate.toStringAsFixed(2)}%',
                style: TextStyle(
                    fontSize: AppTextSize.md, color: Color(0xFF475569)),
              ),
              Text(_fmtDate.format(createdAt.toLocal()),
                  style: TextStyle(
                      fontSize: AppTextSize.xs, color: Color(0xFF94A3B8))),
              const Divider(height: 24),

              // Side-by-side comparison
              Row(children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(
                    flex: 4,
                    child: _CompDetailHeader(
                        isEs ? '30 años' : '30-Year', AppTheme.primary)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                    flex: 4,
                    child: _CompDetailHeader(
                        isEs ? '15 años' : '15-Year', AppTheme.accentGood)),
              ]),
              const SizedBox(height: AppSpacing.smPlus),
              _CompDetailRow(
                label: isEs ? 'Mensual' : 'Monthly',
                v30: AmountFormatter.ui(m30, 'USD'),
                v15: AmountFormatter.ui(m15, 'USD'),
                winnerIs15: m15 < m30,
              ),
              _CompDetailRow(
                label: isEs ? 'Interés total' : 'Total Interest',
                v30: AmountFormatter.ui(i30, 'USD'),
                v15: AmountFormatter.ui(i15, 'USD'),
                winnerIs15: i15 < i30,
              ),
              _CompDetailRow(
                label: isEs ? 'Ahorro en interés' : 'Interest Saved',
                v30: '—',
                v15: AmountFormatter.ui(i30 - i15, 'USD'),
                winnerIs15: true,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Savings callout
              Container(
                padding: const EdgeInsets.all(AppSpacing.mdPlus),
                decoration: BoxDecoration(
                  color: AppTheme.accentGood.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                  border: Border.all(
                      color: AppTheme.accentGood.withValues(alpha: 0.3)),
                ),
                child: Text(
                  isEs
                      ? 'El plan de 15 años ahorra ${AmountFormatter.ui(i30 - i15, 'USD')} en interés total, '
                          'pagando ${AmountFormatter.ui(m15 - m30, 'USD')} más por mes.'
                      : '15-year saves ${AmountFormatter.ui(i30 - i15, 'USD')} in total interest, '
                          'paying ${AmountFormatter.ui(m15 - m30, 'USD')} more per month.',
                  style: TextStyle(
                      fontSize: AppTextSize.md, color: Color(0xFF334155)),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // PDF export — two buttons
              _SectionTitle(isEs ? 'Exportar PDF' : 'Export PDF'),
              const SizedBox(height: AppSpacing.sm),
              ValueListenableBuilder<bool>(
                valueListenable: freemiumService.hasFullAccessNotifier,
                builder: (context, isPremium, _) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: freemiumService.isRewardedNotifier,
                  builder: (context, isRewarded, _) {
                    final unlocked = isPremium || isRewarded;
                    return Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: unlocked
                              ? () => _exportPdf(ctx, r30row)
                              : () => PdfExportService.showUnlockOrPay(
                                  ctx, () => _exportPdf(ctx, r30row)),
                          icon: Icon(
                              unlocked
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.lock_outline,
                              size: 18,
                              color: unlocked
                                  ? AppTheme.primary
                                  : const Color(0xFF64748B)),
                          label: Text(
                              unlocked
                                  ? (isEs ? 'PDF — 30 años' : 'PDF — 30-Year')
                                  : (isEs
                                      ? 'PDF — 30 años (Premium)'
                                      : 'PDF — 30-Year (Premium)'),
                              style: TextStyle(
                                  color: unlocked
                                      ? AppTheme.primary
                                      : const Color(0xFF64748B))),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md),
                            side: BorderSide(
                                color: unlocked
                                    ? AppTheme.primary
                                    : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: unlocked
                              ? () => _exportPdf(ctx, r15row)
                              : () => PdfExportService.showUnlockOrPay(
                                  ctx, () => _exportPdf(ctx, r15row)),
                          icon: Icon(
                              unlocked
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.lock_outline,
                              size: 18,
                              color: unlocked
                                  ? AppTheme.accentGood
                                  : const Color(0xFF64748B)),
                          label: Text(
                              unlocked
                                  ? (isEs ? 'PDF — 15 años' : 'PDF — 15-Year')
                                  : (isEs
                                      ? 'PDF — 15 años (Premium)'
                                      : 'PDF — 15-Year (Premium)'),
                              style: TextStyle(
                                  color: unlocked
                                      ? AppTheme.accentGood
                                      : const Color(0xFF64748B))),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md),
                            side: BorderSide(
                                color: unlocked
                                    ? AppTheme.accentGood
                                    : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ]);
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future.delayed(const Duration(milliseconds: 200));
                    if (context.mounted) _deleteComparison(cid, context);
                  },
                  icon: Icon(Icons.delete_outline,
                      size: 18,
                      color: CalcwiseSemanticColors.error(
                          Theme.of(context).brightness)),
                  label: Text(
                      isEs ? 'Eliminar comparación' : 'Delete comparison',
                      style: TextStyle(
                          color: CalcwiseSemanticColors.error(
                              Theme.of(context).brightness))),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    side: BorderSide(
                        color: CalcwiseSemanticColors.error(
                            Theme.of(context).brightness)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Compare mode helpers ──────────────────────────────────────────────────

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else if (_selectedIds.length < 2) {
        _selectedIds.add(id);
      }
    });
  }

  void _openCompareScreen(BuildContext context, bool isEs) {
    if (_selectedIds.length != 2) return;
    final ids = _selectedIds.toList();
    final row1 = _history.firstWhere((r) => r['id'] == ids[0]);
    final row2 = _history.firstWhere((r) => r['id'] == ids[1]);
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) =>
            _HistoryCompareScreen(row1: row1, row2: row2, isEs: isEs),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: AppDuration.base,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final AppStrings str = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
            appBar: AppBar(
              title: Text(str.navHistory),
              actions: [
                if (_compareMode && _selectedIds.length == 2)
                  TextButton(
                    onPressed: () => _openCompareScreen(context, isEs),
                    child: Text(
                      isEs ? 'Comparar' : 'Compare Selected',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                IconButton(
                  icon: Icon(_compareMode
                      ? Icons.close_rounded
                      : Icons.compare_arrows),
                  tooltip: _compareMode
                      ? (isEs ? 'Cancelar' : 'Cancel')
                      : (isEs ? 'Comparar' : 'Compare'),
                  onPressed: () {
                    setState(() {
                      _compareMode = !_compareMode;
                      _selectedIds.clear();
                    });
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: _firstLoad
                      ? const _HistorySkeleton()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.lg,
                                      AppSpacing.lg,
                                      AppSpacing.lg,
                                      AppSpacing.sm),
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable:
                                        freemiumService.hasFullAccessNotifier,
                                    builder: (context, isPremium, _) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(
                                              child: Text(
                                                isPremium
                                                    ? '${_items.length} ${isEs ? 'entradas guardadas' : 'entries saved'}'
                                                    : '${_items.length} / ${MonetizationConfig.freeCalculationLimit} ${isEs ? 'guardados' : 'saved'}',
                                                style: TextStyle(
                                                    color: Color(0xFF475569),
                                                    fontSize: AppTextSize.md),
                                              ),
                                            ),
                                            if (isPremium &&
                                                _history.isNotEmpty)
                                              TextButton.icon(
                                                onPressed: () async {
                                                  final confirm =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) =>
                                                        AlertDialog(
                                                      title: Text(isEs
                                                          ? '¿Borrar todo?'
                                                          : 'Clear all?'),
                                                      content: Text(isEs
                                                          ? '¿Eliminar todo el historial?'
                                                          : 'Delete all history entries?'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  ctx, false),
                                                          child: Text(isEs
                                                              ? 'Cancelar'
                                                              : 'Cancel'),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  ctx, true),
                                                          child: Text(
                                                              isEs
                                                                  ? 'Borrar'
                                                                  : 'Clear',
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .red)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true)
                                                    _clearAll();
                                                },
                                                icon: Icon(
                                                    Icons.delete_sweep,
                                                    size: 18,
                                                    color:
                                                        CalcwiseSemanticColors
                                                            .error(Theme.of(
                                                                    context)
                                                                .brightness)),
                                                label: Text(
                                                    isEs
                                                        ? 'Borrar todo'
                                                        : 'Clear all',
                                                    style: TextStyle(
                                                        color:
                                                            CalcwiseSemanticColors
                                                                .error(Theme.of(
                                                                        context)
                                                                    .brightness))),
                                              ),
                                          ]),
                                          if (_compareMode) ...[
                                            const SizedBox(
                                                height: AppRadius.sm),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal:
                                                          AppSpacing.smPlus,
                                                      vertical: AppSpacing.sm),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppRadius.md),
                                                border: Border.all(
                                                    color: AppTheme.primary
                                                        .withValues(
                                                            alpha: 0.3)),
                                              ),
                                              child: Row(children: [
                                                const Icon(
                                                    Icons.touch_app_rounded,
                                                    size: 14,
                                                    color: AppTheme.primary),
                                                const SizedBox(
                                                    width: AppRadius.sm),
                                                Expanded(
                                                  child: Text(
                                                    isEs
                                                        ? 'Selecciona 2 entradas para comparar (${_selectedIds.length}/2)'
                                                        : 'Select 2 entries to compare (${_selectedIds.length}/2)',
                                                    style: const TextStyle(
                                                        fontSize:
                                                            AppTextSize.sm,
                                                        color:
                                                            AppTheme.primary),
                                                  ),
                                                ),
                                              ]),
                                            ),
                                          ],
                                          if (!isPremium) ...[
                                            const SizedBox(
                                                height: AppRadius.sm),
                                            Row(children: [
                                              const Icon(Icons.lock_outline,
                                                  size: 14,
                                                  color: CalcwiseSemanticColors
                                                      .warnIcon),
                                              const SizedBox(
                                                  width: AppRadius.sm),
                                              Expanded(
                                                child: Text(
                                                  isEs
                                                      ? 'Máximo ${MonetizationConfig.freeCalculationLimit} entradas para usuarios gratuitos'
                                                      : 'Max ${MonetizationConfig.freeCalculationLimit} entries for free users',
                                                  style: TextStyle(
                                                      fontSize: AppTextSize.sm,
                                                      color: Color(0xFF475569)),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    IAPService.instance.buy(),
                                                style: TextButton.styleFrom(
                                                    padding: EdgeInsets.zero),
                                                child: Text(
                                                  isEs
                                                      ? 'Desbloquear'
                                                      : 'Unlock',
                                                  style: const TextStyle(
                                                      color: AppTheme.primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: AppTextSize.sm),
                                                ),
                                              ),
                                            ]),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (_items.isEmpty)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: CalcwiseEmptyState(
                                    icon: Icons.history_rounded,
                                    title: isEs
                                        ? 'Sin cálculos aún'
                                        : 'No calculations yet',
                                    body: isEs
                                        ? 'Guarda una hipoteca en la pestaña Calculadora para verla aquí.'
                                        : 'Save a mortgage from the Calculator tab to see it here.',
                                    actionLabel: isEs
                                        ? 'Calcular ahora'
                                        : 'Calculate now',
                                    onAction: () => tabSwitchNotifier.value = 0,
                                  ),
                                )
                              else
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) {
                                      final item = _items[i];
                                      final currentGroup =
                                          _dateGroup(_itemDate(item), isEs);
                                      final prevGroup = i == 0
                                          ? null
                                          : _dateGroup(
                                              _itemDate(_items[i - 1]), isEs);
                                      final showHeader =
                                          currentGroup != prevGroup;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (showHeader)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      20, 16, 20, 8),
                                              child: Text(
                                                currentGroup.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: AppTextSize.xs,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                16, 0, 16, 8),
                                            child: item.isComparison
                                                ? _buildComparisonCard(
                                                    context,
                                                    item.comparison!,
                                                    item.comparisonId!,
                                                    isEs)
                                                : Dismissible(
                                                    key: ValueKey(
                                                        'entry-${item.single!['id']}'),
                                                    direction: DismissDirection
                                                        .endToStart,
                                                    background: Container(
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    AppRadius
                                                                        .lg),
                                                      ),
                                                      alignment:
                                                          Alignment.centerRight,
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: AppSpacing
                                                                  .xxl),
                                                      child: const Icon(
                                                          Icons.delete_rounded,
                                                          color: Colors.white),
                                                    ),
                                                    confirmDismiss: (_) async {
                                                      return await _confirmDelete(
                                                              context, isEs) ??
                                                          false;
                                                    },
                                                    onDismissed: (_) async {
                                                      await DatabaseHelper
                                                          .instance
                                                          .deleteHistory(
                                                              item.single!['id']
                                                                  as int);
                                                      _load();
                                                    },
                                                    child: _buildSingleCard(
                                                        context,
                                                        item.single!,
                                                        isEs),
                                                  ),
                                          ),
                                        ],
                                      );
                                    },
                                    childCount: _items.length,
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: AppSpacing.lg)),
                            ],
                          ),
                        ),
                ),
                const CalcwiseAdFooter(),
              ],
            ));
      },
    );
  }

  // ── Card builders ─────────────────────────────────────────────────────────

  Widget _buildSingleCard(
      BuildContext context, Map<String, dynamic> row, bool isEs) {
    final homePrice = (row['home_price'] as num?)?.toDouble() ?? 0.0;
    final annualRate = (row['annual_rate'] as num?)?.toDouble() ?? 0.0;
    final termYears = (row['term_years'] as num?)?.toInt() ?? 30;
    final loanType = row['loan_type'] as String? ?? 'Conventional';
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final id = row['id'] as int? ?? 0;
    final label = row['label'] as String?;
    final humanLabel =
        '${AmountFormatter.ui(homePrice, 'USD')} · ${annualRate.toStringAsFixed(2)}% · ${termYears}${isEs ? 'a' : 'yr'}';

    final isSelected = _selectedIds.contains(id);
    final canSelect = _compareMode && (_selectedIds.length < 2 || isSelected);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: isSelected
            ? BorderSide(color: AppTheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: _compareMode
            ? (canSelect ? () => _toggleSelect(id) : null)
            : () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => HistoryDetailScreen(row: row),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                )),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus, vertical: AppSpacing.md),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label != null && label.isNotEmpty
                                ? label
                                : humanLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.bodyMd,
                                color: AppTheme.primary),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm)),
                            child: Text(loanType,
                                style: const TextStyle(
                                    fontSize: AppTextSize.xs,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary)),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_fmtDate.format(createdAt.toLocal()),
                      style: TextStyle(
                          fontSize: AppTextSize.xs, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            if (_compareMode)
              Checkbox(
                value: isSelected,
                activeColor: AppTheme.primary,
                onChanged: canSelect ? (_) => _toggleSelect(id) : null,
              )
            else
              ValueListenableBuilder<bool>(
                valueListenable: freemiumService.hasFullAccessNotifier,
                builder: (context, isPremium, _) => IconButton(
                  icon: Icon(
                    isPremium
                        ? Icons.picture_as_pdf_rounded
                        : Icons.lock_outline,
                    size: 20,
                    color:
                        isPremium ? AppTheme.primary : const Color(0xFF94A3B8),
                  ),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppRadius.sm),
                  tooltip: isPremium
                      ? (isEs ? 'Exportar PDF' : 'Export PDF')
                      : 'Premium',
                  onPressed: isPremium
                      ? () => _exportPdf(context, row)
                      : () => PdfExportService.showUnlockOrPay(
                          context, () => _exportPdf(context, row)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildComparisonCard(BuildContext context,
      List<Map<String, dynamic>> pair, String cid, bool isEs) {
    final r30row = pair.firstWhere((r) => (r['term_years'] as int? ?? 30) == 30,
        orElse: () => pair.first);
    final r15row = pair.firstWhere((r) => (r['term_years'] as int? ?? 30) == 15,
        orElse: () => pair.last);

    final homePrice = (r30row['home_price'] as num?)?.toDouble() ?? 0.0;
    final loanType = r30row['loan_type'] as String? ?? 'Conventional';
    final createdAt =
        DateTime.tryParse(r30row['created_at'] as String? ?? '') ??
            DateTime.now();
    final m30 = (r30row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final m15 = (r15row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final i30 = (r30row['total_interest'] as num?)?.toDouble() ?? 0.0;
    final i15 = (r15row['total_interest'] as num?)?.toDouble() ?? 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _showComparisonDetail(context, pair, cid, isEs),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus, vertical: AppSpacing.md),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: compare icon + price + badge
                  Row(children: [
                    const Icon(Icons.compare_arrows,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: AppRadius.sm),
                    Text(
                      AmountFormatter.ui(homePrice, 'USD'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.bodyMd,
                          color: AppTheme.primary),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Text(loanType,
                          style: const TextStyle(
                              fontSize: AppTextSize.xs,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ),
                  ]),
                  const SizedBox(height: AppRadius.sm),
                  // Scenario comparison row
                  Row(children: [
                    _ScenarioPill(
                        label: isEs ? '30a' : '30yr',
                        value: AmountFormatter.ui(m30, 'USD'),
                        color: AppTheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    _ScenarioPill(
                        label: isEs ? '15a' : '15yr',
                        value: AmountFormatter.ui(m15, 'USD'),
                        color: AppTheme.accentGood),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        '${isEs ? 'Ahorra' : 'Saves'} ${AmountFormatter.ui(i30 - i15, 'USD')}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppTextSize.xs,
                            color: AppTheme.accentGood,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_fmtDate.format(createdAt.toLocal()),
                      style: TextStyle(
                          fontSize: AppTextSize.xs, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.info_outline,
                      size: 20, color: AppTheme.primary),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppRadius.sm),
                  tooltip: isEs ? 'Ver detalle' : 'View detail',
                  onPressed: () =>
                      _showComparisonDetail(context, pair, cid, isEs),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: CalcwiseSemanticColors.error(
                          Theme.of(context).brightness),
                      size: 20),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppRadius.sm),
                  onPressed: () => _deleteComparison(cid, context),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: List.generate(
            3,
            (i) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _ShimmerBox(
                                width: 120, height: 26, radius: AppRadius.md),
                            const Spacer(),
                            _ShimmerBox(
                                width: 70, height: 22, radius: AppRadius.sm),
                          ]),
                          const SizedBox(height: 12),
                          ...List.generate(
                              4,
                              (_) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _ShimmerBox(
                                            width: 100, height: 13, radius: 4),
                                        _ShimmerBox(
                                            width: 70, height: 13, radius: 4),
                                      ],
                                    ),
                                  )),
                        ],
                      ),
                    ),
                  ),
                )),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width, height, radius;
  const _ShimmerBox(
      {required this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ScenarioPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ScenarioPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          '$label: $value',
          style: TextStyle(
              fontSize: AppTextSize.xs,
              color: color,
              fontWeight: FontWeight.w600),
        ),
      );
}

class _CompDetailHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _CompDetailHeader(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.md)),
      );
}

class _CompDetailRow extends StatelessWidget {
  final String label, v30, v15;
  final bool winnerIs15;
  const _CompDetailRow({
    required this.label,
    required this.v30,
    required this.v15,
    required this.winnerIs15,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: TextStyle(
                      color: Color(0xFF334155), fontSize: AppTextSize.md))),
          Expanded(
              flex: 4,
              child: _CellBox(v30,
                  isWinner: !winnerIs15 && v30 != '—',
                  color: AppTheme.primary)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              flex: 4,
              child: _CellBox(v15,
                  isWinner: winnerIs15, color: AppTheme.accentGood)),
        ]),
      );
}

class _CellBox extends StatelessWidget {
  final String value;
  final bool isWinner;
  final Color color;
  const _CellBox(this.value, {required this.isWinner, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isWinner ? color.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: isWinner
              ? Border.all(color: color.withValues(alpha: 0.35))
              : null,
        ),
        child: Text(value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
                color: isWinner ? color : null)),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: AppTextSize.xs,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
          letterSpacing: 0.8));
}

// ── Compare Bar Chart ─────────────────────────────────────────────────────────

class _CompareBarChart extends StatelessWidget {
  final double monthly1, monthly2;
  final double interest1, interest2;
  final double total1, total2;
  final String labelA, labelB;
  final bool isEs;

  const _CompareBarChart({
    required this.monthly1,
    required this.monthly2,
    required this.interest1,
    required this.interest2,
    required this.total1,
    required this.total2,
    required this.labelA,
    required this.labelB,
    required this.isEs,
  });

  String _kFormat(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    return '\$${(v / 1000).toStringAsFixed(1)}K';
  }

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    const colorA = AppTheme.primary;
    const colorB = Color(0xFF475569); // secondary/slate

    final groups = [
      (isEs ? 'Mensual' : 'Monthly', monthly1, monthly2),
      (isEs ? 'Interés' : 'Interest', interest1, interest2),
      (isEs ? 'Costo total' : 'Total Cost', total1, total2),
    ];

    final maxVal = groups.fold(
        0.0, (m, g) => [m, g.$2, g.$3].reduce((a, b) => a > b ? a : b));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded,
                size: 16, color: AppTheme.primary),
            const SizedBox(width: AppRadius.sm),
            Text(
              isEs ? 'Comparación visual' : 'Visual Comparison',
              style: const TextStyle(
                  fontSize: AppTextSize.md,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                      _kFormat(rod.toY),
                      const TextStyle(
                          color: Colors.white,
                          fontSize: AppTextSize.xs,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= groups.length)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            groups[idx].$1,
                            style: TextStyle(
                                fontSize: AppTextSize.xs, color: ct.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, _) => Text(
                        _kFormat(v),
                        style: TextStyle(
                            fontSize: AppTextSize.xxs, color: ct.textSecondary),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(groups.length, (i) {
                  final g = groups[i];
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: g.$2,
                        color: colorA,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        rodStackItems: [],
                      ),
                      BarChartRodData(
                        toY: g.$3,
                        color: colorB,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        rodStackItems: [],
                      ),
                    ],
                    barsSpace: 4,
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Legend
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _BarLegendDot(color: colorA, label: labelA),
            const SizedBox(width: AppSpacing.xl),
            _BarLegendDot(color: colorB, label: labelB),
          ]),
        ]),
      ),
    );
  }
}

class _BarLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _BarLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: AppTextSize.xs, color: Color(0xFF475569)),
          ),
        ],
      );
}

// ── History Compare Screen ────────────────────────────────────────────────────

class _HistoryCompareScreen extends StatelessWidget {
  final Map<String, dynamic> row1;
  final Map<String, dynamic> row2;
  final bool isEs;

  const _HistoryCompareScreen({
    required this.row1,
    required this.row2,
    required this.isEs,
  });

  static final _fmtDate = DateFormat('MMM d, yyyy');

  String _colLabel(Map<String, dynamic> row) {
    final label = row['label'] as String?;
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    return (label != null && label.isNotEmpty)
        ? label
        : _fmtDate.format(createdAt.toLocal());
  }

  String _fmt(dynamic v) => AmountFormatter.ui((v as num?)?.toDouble() ?? 0.0, 'USD');

  Color _winner(double v1, double v2, {required bool lowerIsBetter}) {
    if (lowerIsBetter)
      return v1 < v2 ? AppTheme.accentGood : const Color(0xFFEF4444);
    return v1 > v2 ? AppTheme.accentGood : const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final monthly1 = (row1['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final monthly2 = (row2['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final interest1 = (row1['total_interest'] as num?)?.toDouble() ?? 0.0;
    final interest2 = (row2['total_interest'] as num?)?.toDouble() ?? 0.0;
    final price1 = (row1['home_price'] as num?)?.toDouble() ?? 0.0;
    final price2 = (row2['home_price'] as num?)?.toDouble() ?? 0.0;
    final rate1 = (row1['annual_rate'] as num?)?.toDouble() ?? 0.0;
    final rate2 = (row2['annual_rate'] as num?)?.toDouble() ?? 0.0;
    final term1 = (row1['term_years'] as num?)?.toInt() ?? 30;
    final term2 = (row2['term_years'] as num?)?.toInt() ?? 30;
    final total1 = monthly1 * term1 * 12;
    final total2 = monthly2 * term2 * 12;

    final col1 = _colLabel(row1);
    final col2 = _colLabel(row2);

    final rows = <_CRow>[
      _CRow(
        label: isEs ? 'Pago mensual' : 'Monthly Payment',
        v1: _fmt(monthly1),
        v2: _fmt(monthly2),
        c1: _winner(monthly1, monthly2, lowerIsBetter: true),
        c2: _winner(monthly2, monthly1, lowerIsBetter: true),
      ),
      _CRow(
        label: isEs ? 'Interés total' : 'Total Interest',
        v1: _fmt(interest1),
        v2: _fmt(interest2),
        c1: _winner(interest1, interest2, lowerIsBetter: true),
        c2: _winner(interest2, interest1, lowerIsBetter: true),
      ),
      _CRow(
        label: isEs ? 'Costo total' : 'Total Cost',
        v1: _fmt(total1),
        v2: _fmt(total2),
        c1: _winner(total1, total2, lowerIsBetter: true),
        c2: _winner(total2, total1, lowerIsBetter: true),
      ),
      _CRow(
        label: isEs ? 'Precio vivienda' : 'Home Price',
        v1: _fmt(price1),
        v2: _fmt(price2),
        c1: null,
        c2: null,
      ),
      _CRow(
        label: isEs ? 'Tasa' : 'Rate',
        v1: '${rate1.toStringAsFixed(2)}%',
        v2: '${rate2.toStringAsFixed(2)}%',
        c1: _winner(rate1, rate2, lowerIsBetter: true),
        c2: _winner(rate2, rate1, lowerIsBetter: true),
      ),
      _CRow(
        label: isEs ? 'Plazo' : 'Term',
        v1: isEs ? '$term1 años' : '$term1 yr',
        v2: isEs ? '$term2 años' : '$term2 yr',
        c1: null,
        c2: null,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? 'Comparar escenarios' : 'Compare Scenarios'),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Column headers
              Row(children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.smPlus, horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      col1,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.sm),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.smPlus, horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF475569),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      col2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.sm),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              ...rows.map((r) => _CompareRowWidget(row: r)),
              const SizedBox(height: AppSpacing.xxl),
              // Color legend
              Row(children: [
                const Icon(Icons.circle, size: 10, color: AppTheme.accentGood),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  isEs ? 'Mejor valor' : 'Better value',
                  style: const TextStyle(
                      fontSize: AppTextSize.sm, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: AppSpacing.lg),
                const Icon(Icons.circle, size: 10, color: Color(0xFFEF4444)),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  isEs ? 'Valor más alto' : 'Higher value',
                  style: const TextStyle(
                      fontSize: AppTextSize.sm, color: Color(0xFF64748B)),
                ),
              ]),
              const SizedBox(height: AppSpacing.xxl),

              // ── Bar chart comparison ──
              _CompareBarChart(
                monthly1: monthly1,
                monthly2: monthly2,
                interest1: interest1,
                interest2: interest2,
                total1: total1,
                total2: total2,
                labelA: col1,
                labelB: col2,
                isEs: isEs,
              ),
              const SizedBox(height: AppSpacing.listBottomInset),
            ]),
          ),
        ),
        const CalcwiseAdFooter(),
      ]),
    );
  }
}

class _CRow {
  final String label, v1, v2;
  final Color? c1, c2;
  const _CRow(
      {required this.label,
      required this.v1,
      required this.v2,
      required this.c1,
      required this.c2});
}

class _CompareRowWidget extends StatelessWidget {
  final _CRow row;
  const _CompareRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Text(row.label,
              style: const TextStyle(
                  fontSize: AppTextSize.md, color: Color(0xFF334155))),
        ),
        Expanded(
          flex: 4,
          child: _CellBadge(value: row.v1, color: row.c1),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 4,
          child: _CellBadge(value: row.v2, color: row.c2),
        ),
      ]),
    );
  }
}

class _CellBadge extends StatelessWidget {
  final String value;
  final Color? color;
  const _CellBadge({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isHighlighted = color != null;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isHighlighted ? color!.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: isHighlighted
            ? Border.all(color: color!.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppTextSize.sm,
          fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
          color: isHighlighted ? color : null,
        ),
      ),
    );
  }
}

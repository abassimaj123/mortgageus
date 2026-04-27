import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/freemium/freemium_service.dart';
import '../../../core/freemium/iap_service.dart';
import '../../../core/ads/ad_footer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/pdf_export_service.dart';
import '../../../domain/models/loan_type.dart';
import '../../../domain/models/mortgage_input.dart';
import '../../../domain/usecases/mortgage_calculator.dart';
import '../../../core/constants/mortgage_constants.dart';
import '../../providers/mortgage_providers.dart';
import '../../../main.dart' show isSpanishNotifier;
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_es.dart';
import 'history_detail_screen.dart';

// ── Item model for grouped display ───────────────────────────────────────────

class _HistoryItem {
  final Map<String, dynamic>?       single;
  final List<Map<String, dynamic>>? comparison; // [r30, r15] or [r15, r30]
  final String?                     comparisonId;

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
  List<_HistoryItem>         _items   = [];
  bool _firstLoad = true;

  final _fmtUSD  = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
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
    final items    = <_HistoryItem>[];
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
        _history    = rows;
        _items      = _groupRows(rows);
        _firstLoad  = false;
      });
    }
  }

  Future<void> _silentRefresh() async {
    final rows = await DatabaseHelper.instance.getHistory();
    if (mounted) {
      setState(() {
        _history = rows;
        _items   = _groupRows(rows);
      });
    }
  }

  // ── Delete helpers ────────────────────────────────────────────────────────

  Future<void> _delete(int id, BuildContext context) async {
    final isEs   = isSpanishNotifier.value;
    final confirm = await _confirmDelete(context, isEs);
    if (confirm == true) {
      await DatabaseHelper.instance.deleteHistory(id);
      _load();
    }
  }

  Future<void> _deleteComparison(String comparisonId, BuildContext context) async {
    final isEs   = isSpanishNotifier.value;
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
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll() async {
    await DatabaseHelper.instance.clearHistory();
    _load();
  }

  // ── LoanType helper ───────────────────────────────────────────────────────

  LoanType _parseLoanType(String label) {
    switch (label) {
      case 'FHA':   return LoanType.fha;
      case 'VA':    return LoanType.va;
      case 'Jumbo': return LoanType.jumbo;
      default:      return LoanType.conventional;
    }
  }

  // ── PDF export ────────────────────────────────────────────────────────────

  Future<void> _exportPdf(BuildContext context, Map<String, dynamic> row) async {
    final homePrice   = (row['home_price']   as num?)?.toDouble()  ?? 0.0;
    final downPercent = (row['down_percent'] as num?)?.toDouble()  ?? 20.0;
    final annualRate  = (row['annual_rate']  as num?)?.toDouble()  ?? 6.5;
    final termYears   = (row['term_years']   as num?)?.toInt()     ?? 30;
    final taxRate     = (row['tax_rate']     as num?)?.toDouble()  ?? MortgageConstants.defaultPropertyTaxRate;
    final insurance   = (row['insurance']    as num?)?.toDouble()  ?? MortgageConstants.defaultHomeInsurance;
    final hoa         = (row['hoa']          as num?)?.toDouble()  ?? 0.0;
    final loanType    = _parseLoanType(row['loan_type'] as String? ?? 'Conventional');

    final downPayment = homePrice * downPercent / 100.0;
    final loanAmount  = homePrice - downPayment;
    final ltv         = homePrice > 0 ? loanAmount / homePrice * 100 : 0.0;
    final pmiRate     = (ltv > 80.0 && loanType != LoanType.va)
        ? MortgageConstants.pmiDefaultAnnualRate * 100
        : 0.0;

    final inputState = MortgageInputState(
      homePrice:           homePrice,
      downPaymentPct:      downPercent,
      annualRatePct:       annualRate,
      termYears:           termYears,
      loanType:            loanType,
      propertyTaxRatePct:  taxRate,
      homeInsuranceAnnual: insurance,
      hoaMonthly:          hoa,
    );

    final now = DateTime.now();
    final input = MortgageInput(
      homePrice:            homePrice,
      downPayment:          downPayment,
      annualRatePct:        annualRate,
      termYears:            termYears,
      loanType:             loanType,
      propertyTaxRatePct:   taxRate,
      homeInsuranceAnnual:  insurance,
      hoaMonthly:           hoa,
      pmiAnnualRatePct:     pmiRate,
      startDate:            DateTime(now.year, now.month + 1),
    );

    try {
      final result = MortgageCalculator.calculate(input);
      if (context.mounted) {
        await PdfExportService.exportMortgage(context, inputState, result);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  // ── Detail sheet (comparison only — singles go to HistoryDetailScreen) ──────

  void _showComparisonDetail(
      BuildContext context, List<Map<String, dynamic>> pair, String cid, bool isEs) {
    // pair is [r30, r15] — sorted by term_years DESC when built
    final r30row = pair.firstWhere(
        (r) => (r['term_years'] as int? ?? 30) == 30,
        orElse: () => pair.first);
    final r15row = pair.firstWhere(
        (r) => (r['term_years'] as int? ?? 30) == 15,
        orElse: () => pair.last);

    final homePrice      = (r30row['home_price']   as num?)?.toDouble() ?? 0.0;
    final annualRate     = (r30row['annual_rate']  as num?)?.toDouble() ?? 0.0;
    final loanType       = r30row['loan_type'] as String? ?? 'Conventional';
    final createdAt      = DateTime.tryParse(r30row['created_at'] as String? ?? '') ?? DateTime.now();

    final m30 = (r30row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final m15 = (r15row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final i30 = (r30row['total_interest']  as num?)?.toDouble() ?? 0.0;
    final i15 = (r15row['total_interest']  as num?)?.toDouble() ?? 0.0;

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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListView(
            controller: controller,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Title
              Row(children: [
                const Icon(Icons.compare_arrows, color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEs ? 'Comparación guardada' : 'Saved comparison',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: AppTheme.primary),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${_fmtUSD.format(homePrice)} · $loanType · ${annualRate.toStringAsFixed(2)}%',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              Text(_fmtDate.format(createdAt.toLocal()),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              const Divider(height: 24),

              // Side-by-side comparison
              Row(children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(flex: 4, child: _CompDetailHeader(
                    isEs ? '30 años' : '30-Year', AppTheme.primary)),
                const SizedBox(width: 8),
                Expanded(flex: 4, child: _CompDetailHeader(
                    isEs ? '15 años' : '15-Year', AppTheme.accentGood)),
              ]),
              const SizedBox(height: 10),
              _CompDetailRow(
                label: isEs ? 'Mensual' : 'Monthly',
                v30: _fmtUSD.format(m30),
                v15: _fmtUSD.format(m15),
                winnerIs15: m15 < m30,
              ),
              _CompDetailRow(
                label: isEs ? 'Interés total' : 'Total Interest',
                v30: _fmtUSD.format(i30),
                v15: _fmtUSD.format(i15),
                winnerIs15: i15 < i30,
              ),
              _CompDetailRow(
                label: isEs ? 'Ahorro en interés' : 'Interest Saved',
                v30: '—',
                v15: _fmtUSD.format(i30 - i15),
                winnerIs15: true,
              ),
              const SizedBox(height: 16),

              // Savings callout
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accentGood.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentGood.withValues(alpha: 0.3)),
                ),
                child: Text(
                  isEs
                      ? 'El plan de 15 años ahorra ${_fmtUSD.format(i30 - i15)} en interés total, '
                        'pagando ${_fmtUSD.format(m15 - m30)} más por mes.'
                      : '15-year saves ${_fmtUSD.format(i30 - i15)} in total interest, '
                        'paying ${_fmtUSD.format(m15 - m30)} more per month.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
              const SizedBox(height: 24),

              // PDF export — two buttons
              _SectionTitle(isEs ? 'Exportar PDF' : 'Export PDF'),
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: freemiumService.isPremiumNotifier,
                builder: (context, isPremium, _) => Column(children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isPremium
                          ? () => _exportPdf(ctx, r30row)
                          : () => PdfExportService.showUnlockOrPay(
                              ctx, () => _exportPdf(ctx, r30row)),
                      icon: Icon(
                          isPremium ? Icons.picture_as_pdf_outlined : Icons.lock_outline,
                          size: 18,
                          color: isPremium ? AppTheme.primary : Colors.grey),
                      label: Text(
                          isPremium
                              ? (isEs ? 'PDF — 30 años' : 'PDF — 30-Year')
                              : (isEs ? 'PDF — 30 años (Premium)' : 'PDF — 30-Year (Premium)'),
                          style: TextStyle(
                              color: isPremium ? AppTheme.primary : Colors.grey.shade500)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                            color: isPremium
                                ? AppTheme.primary
                                : Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isPremium
                          ? () => _exportPdf(ctx, r15row)
                          : () => PdfExportService.showUnlockOrPay(
                              ctx, () => _exportPdf(ctx, r15row)),
                      icon: Icon(
                          isPremium ? Icons.picture_as_pdf_outlined : Icons.lock_outline,
                          size: 18,
                          color: isPremium ? AppTheme.accentGood : Colors.grey),
                      label: Text(
                          isPremium
                              ? (isEs ? 'PDF — 15 años' : 'PDF — 15-Year')
                              : (isEs ? 'PDF — 15 años (Premium)' : 'PDF — 15-Year (Premium)'),
                          style: TextStyle(
                              color: isPremium
                                  ? AppTheme.accentGood
                                  : Colors.grey.shade500)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                            color: isPremium
                                ? AppTheme.accentGood
                                : Colors.grey.shade300),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Future.delayed(const Duration(milliseconds: 200));
                    if (context.mounted) _deleteComparison(cid, context);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: Text(
                      isEs ? 'Eliminar comparación' : 'Delete comparison',
                      style: const TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        final dynamic str = isEs ? AppStringsES() : AppStringsEN();
        return Scaffold(
          appBar: AppBar(title: Text(str.navHistory)),
          body: Column(
          children: [
            Expanded(
              child: _firstLoad
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: ValueListenableBuilder<bool>(
                                valueListenable: freemiumService.isPremiumNotifier,
                                builder: (context, isPremium, _) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(
                                            isPremium
                                                ? '${_items.length} ${isEs ? 'entradas guardadas' : 'entries saved'}'
                                                : '${_items.length} / ${FreemiumService.freeHistoryLimit} ${isEs ? 'guardados' : 'saved'}',
                                            style: TextStyle(
                                                color: Colors.grey.shade600, fontSize: 13),
                                          ),
                                        ),
                                        if (isPremium && _history.isNotEmpty)
                                          TextButton.icon(
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: Text(isEs ? '¿Borrar todo?' : 'Clear all?'),
                                                  content: Text(isEs
                                                      ? '¿Eliminar todo el historial?'
                                                      : 'Delete all history entries?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, false),
                                                      child: Text(isEs ? 'Cancelar' : 'Cancel'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      child: Text(isEs ? 'Borrar' : 'Clear',
                                                          style: const TextStyle(color: Colors.red)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) _clearAll();
                                            },
                                            icon: const Icon(Icons.delete_sweep,
                                                size: 18, color: Colors.red),
                                            label: Text(isEs ? 'Borrar todo' : 'Clear all',
                                                style: const TextStyle(color: Colors.red)),
                                          ),
                                      ]),
                                      if (!isPremium) ...[
                                        const SizedBox(height: 6),
                                        Row(children: [
                                          const Icon(Icons.lock_outline,
                                              size: 14, color: Colors.amber),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              isEs
                                                  ? 'Máximo ${FreemiumService.freeHistoryLimit} entradas para usuarios gratuitos'
                                                  : 'Max ${FreemiumService.freeHistoryLimit} entries for free users',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => IAPService.instance.buy(),
                                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                            child: Text(
                                              isEs ? 'Desbloquear' : 'Unlock',
                                              style: const TextStyle(
                                                  color: AppTheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12),
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
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history,
                                        size: 64, color: Colors.grey.shade300),
                                    const SizedBox(height: 16),
                                    Text(
                                      isEs ? 'Sin historial aún' : 'No history yet',
                                      style: TextStyle(
                                          color: Colors.grey.shade500, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isEs
                                          ? 'Haz un cálculo para comenzar'
                                          : 'Run a calculation to get started',
                                      style: TextStyle(
                                          color: Colors.grey.shade400, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final item = _items[i];
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: item.isComparison
                                        ? _buildComparisonCard(
                                            context, item.comparison!,
                                            item.comparisonId!, isEs)
                                        : _buildSingleCard(
                                            context, item.single!, isEs),
                                  );
                                },
                                childCount: _items.length,
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        ],
                      ),
                    ),
            ),
            const AdFooter(),
          ],
        ));
      },
    );
  }

  // ── Card builders ─────────────────────────────────────────────────────────

  Widget _buildSingleCard(
      BuildContext context, Map<String, dynamic> row, bool isEs) {
    final homePrice      = (row['home_price']      as num?)?.toDouble() ?? 0.0;
    final monthlyPayment = (row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final loanType       = row['loan_type']  as String? ?? 'Conventional';
    final createdAt      = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final id             = row['id'] as int? ?? 0;
    final label          = row['label'] as String?;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => HistoryDetailScreen(row: row))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          if (label != null && label.isNotEmpty)
                            Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.primary)),
                          Row(children: [
                            Text(
                              _fmtUSD.format(homePrice),
                              style: TextStyle(
                                  fontWeight: label != null && label.isNotEmpty
                                      ? FontWeight.w400
                                      : FontWeight.bold,
                                  fontSize: label != null && label.isNotEmpty ? 12 : 15,
                                  color: label != null && label.isNotEmpty
                                      ? Colors.grey.shade500
                                      : AppTheme.primary),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6)),
                              child: Text(loanType,
                                  style: const TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w600,
                                      color: AppTheme.primary)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '${isEs ? 'Pago mensual' : 'Monthly'}: ${_fmtUSD.format(monthlyPayment)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 2),
                  Text(_fmtDate.format(createdAt.toLocal()),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: freemiumService.isPremiumNotifier,
                  builder: (context, isPremium, _) => IconButton(
                    icon: Icon(
                      isPremium
                          ? Icons.picture_as_pdf_outlined
                          : Icons.lock_outline,
                      size: 20,
                      color: isPremium ? AppTheme.primary : Colors.grey.shade400,
                    ),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    tooltip: isPremium
                        ? (isEs ? 'Exportar PDF' : 'Export PDF')
                        : 'Premium',
                    onPressed: isPremium
                        ? () => _exportPdf(context, row)
                        : () => PdfExportService.showUnlockOrPay(
                            context, () => _exportPdf(context, row)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                  onPressed: () => _delete(id, context),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildComparisonCard(BuildContext context,
      List<Map<String, dynamic>> pair, String cid, bool isEs) {
    final r30row = pair.firstWhere(
        (r) => (r['term_years'] as int? ?? 30) == 30,
        orElse: () => pair.first);
    final r15row = pair.firstWhere(
        (r) => (r['term_years'] as int? ?? 30) == 15,
        orElse: () => pair.last);

    final homePrice = (r30row['home_price']      as num?)?.toDouble() ?? 0.0;
    final loanType  = r30row['loan_type'] as String? ?? 'Conventional';
    final createdAt = DateTime.tryParse(r30row['created_at'] as String? ?? '') ?? DateTime.now();
    final m30       = (r30row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final m15       = (r15row['monthly_payment'] as num?)?.toDouble() ?? 0.0;
    final i30       = (r30row['total_interest']  as num?)?.toDouble() ?? 0.0;
    final i15       = (r15row['total_interest']  as num?)?.toDouble() ?? 0.0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showComparisonDetail(context, pair, cid, isEs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: compare icon + price + badge
                  Row(children: [
                    const Icon(Icons.compare_arrows,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      _fmtUSD.format(homePrice),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(loanType,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  // Scenario comparison row
                  Row(children: [
                    _ScenarioPill(
                        label: isEs ? '30a' : '30yr',
                        value: _fmtUSD.format(m30),
                        color: AppTheme.primary),
                    const SizedBox(width: 8),
                    _ScenarioPill(
                        label: isEs ? '15a' : '15yr',
                        value: _fmtUSD.format(m15),
                        color: AppTheme.accentGood),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${isEs ? 'Ahorra' : 'Saves'} ${_fmtUSD.format(i30 - i15)}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.accentGood,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(_fmtDate.format(createdAt.toLocal()),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
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
                  padding: const EdgeInsets.all(6),
                  tooltip: isEs ? 'Ver detalle' : 'View detail',
                  onPressed: () => _showComparisonDetail(context, pair, cid, isEs),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
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

class _ScenarioPill extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _ScenarioPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      '$label: $value',
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _CompDetailHeader extends StatelessWidget {
  final String label;
  final Color  color;
  const _CompDetailHeader(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8)),
    child: Text(label,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
  );
}

class _CompDetailRow extends StatelessWidget {
  final String label, v30, v15;
  final bool   winnerIs15;
  const _CompDetailRow({
    required this.label,
    required this.v30,
    required this.v15,
    required this.winnerIs15,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Expanded(flex: 3,
          child: Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
      Expanded(flex: 4,
          child: _CellBox(v30,
              isWinner: !winnerIs15 && v30 != '—', color: AppTheme.primary)),
      const SizedBox(width: 8),
      Expanded(flex: 4,
          child: _CellBox(v15,
              isWinner: winnerIs15, color: AppTheme.accentGood)),
    ]),
  );
}

class _CellBox extends StatelessWidget {
  final String value;
  final bool   isWinner;
  final Color  color;
  const _CellBox(this.value, {required this.isWinner, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: isWinner ? color.withValues(alpha: 0.1) : null,
      borderRadius: BorderRadius.circular(6),
      border: isWinner ? Border.all(color: color.withValues(alpha: 0.35)) : null,
    ),
    child: Text(value,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 12,
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
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8));
}


import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../presentation/providers/mortgage_providers.dart';
import '../../domain/models/mortgage_result.dart';
import '../../domain/models/loan_type.dart';
import '../freemium/iap_service.dart';
import '../theme/app_theme.dart';
import '../../main.dart' show adService, isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart';

// App navy color in PDF space
const _navy = PdfColor(0.106, 0.227, 0.420); // #1B3A6B
const _gold = PdfColor(0.831, 0.627, 0.090); // #D4A017
const _light = PdfColor(0.945, 0.957, 0.980); // light blue-grey row alt

// TODO: migrate to PdfBrandHelper (calcwise_core/widgets/pdf_brand_helper.dart).
// MortgageUS uses a bespoke navy/gold brand + custom amortization header that
// embeds loan params (rate, term, type) and a custom disclaimer footer.
// When migrating: replace _amortHeader/_footer/_footerNote with
// PdfBrandHelper.pageTheme(appName: 'MortgageUS', brandColor: _navy) on the
// summary page, and keep _amortHeader as-is for the amortization MultiPage
// (it carries loan-specific context the generic helper doesn't model yet).
class PdfExportService {
  static final _usd2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  static final _usd0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  static final _dateLong = DateFormat('MMMM d, yyyy');
  static final _dateShort = DateFormat('MMM yy');

  // ── Public entry point ────────────────────────────────────────────────────

  static Future<void> exportMortgage(
    BuildContext context,
    MortgageInputState input,
    MortgageResult result, {
    bool isEs = false,
  }) async {
    final pdf = pw.Document();

    // ── Page 1 : full summary ─────────────────────────────────────────────
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) => _buildSummaryPage(input, result, isEs: isEs),
    ));

    // ── Pages 2+ : amortization schedule (auto-paginated) ─────────────────
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      header: (ctx) => _amortHeader(input, result, ctx.pageNumber, isEs: isEs),
      footer: (ctx) => _footer(ctx, isEs: isEs),
      build: (_) => [
        ..._buildYearlySection(result, isEs: isEs),
        pw.SizedBox(height: 18),
        ..._buildMonthlySection(result, isEs: isEs),
      ],
    ));

    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_${input.homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  // ── Page 1 builder ────────────────────────────────────────────────────────

  static pw.Widget _buildSummaryPage(
      MortgageInputState input, MortgageResult result,
      {bool isEs = false}) {
    final now = DateTime.now();
    // ── Translated strings ──
    final tReport = isEs ? 'Informe de Cálculo Hipotecario' : 'Mortgage Calculation Report';
    final tLoanDetails = isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tHomePrice = isEs ? 'Precio de la casa' : 'Home Price';
    final tDownPayment = isEs ? 'Enganche' : 'Down Payment';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tInterestRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tLoanTerm = isEs ? 'Plazo' : 'Loan Term';
    final tYears = isEs ? 'años' : 'years';
    final tLoanType = isEs ? 'Tipo de préstamo' : 'Loan Type';
    final tLtv = 'LTV';
    final tClassification = isEs ? 'Clasificación' : 'Classification';
    final tJumbo = isEs ? 'PRÉSTAMO JUMBO' : 'JUMBO LOAN';
    final tTotalCostSection = isEs ? 'COSTO TOTAL' : 'TOTAL COST';
    final tTotalInterest = isEs ? 'Interés total' : 'Total Interest';
    final tTotalCost = isEs ? 'Costo total' : 'Total Cost';
    final tPayoffDate = isEs ? 'Fecha de liquidación' : 'Payoff Date';
    final tPmi = 'PMI';
    final tMonthlyPmi = isEs ? 'PMI mensual' : 'Monthly PMI';
    final tPmiDropsAt = isEs ? 'PMI cae en' : 'PMI Drops at';
    final tMonth = isEs ? 'Mes' : 'Month';
    final tPmiNote = isEs ? 'Se requiere 80% LTV para cancelar' : '80% LTV required to cancel';
    final tMonthlyBreakdown = isEs ? 'DESGLOSE MENSUAL' : 'MONTHLY BREAKDOWN';
    final tPandI = isEs ? 'Capital e Interés' : 'P & I';
    final tPrincipal = isEs ? '  Capital' : '  Principal';
    final tInterest = isEs ? '  Interés' : '  Interest';
    final tPropertyTax = isEs ? 'Impuesto predial' : 'Property Tax';
    final tHomeInsurance = isEs ? 'Seguro del hogar' : 'Home Insurance';
    final tHoa = 'HOA';
    final tTotal = isEs ? 'Total (PITI)' : 'Total (PITI)';
    final tPrincipalVsInterest = isEs ? 'CAPITAL vs INTERÉS' : 'PRINCIPAL vs INTEREST';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── App header ──
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MortgageUS',
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy)),
                  pw.Text(tReport,
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong.format(now),
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),

        // ── Two-column layout ──
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left column
            pw.Expanded(
                child: pw.Column(children: [
              _sectionBox(tLoanDetails, [
                _row2(tHomePrice, _usd0.format(input.homePrice)),
                _row2(tDownPayment,
                    '${_usd0.format(input.downPaymentDollar)} (${input.downPaymentPct.toStringAsFixed(1)}%)'),
                _row2(tLoanAmount, _usd0.format(result.loanAmount)),
                _row2(tInterestRate,
                    '${input.annualRatePct.toStringAsFixed(2)}%'),
                _row2(tLoanTerm, '${input.termYears} $tYears'),
                _row2(tLoanType, input.loanType.label),
                _row2(tLtv, '${result.currentLtv.toStringAsFixed(1)}%'),
                if (result.isJumbo)
                  _row2(tClassification, tJumbo, highlight: true),
              ]),
              pw.SizedBox(height: 10),
              _sectionBox(tTotalCostSection, [
                _row2(tTotalInterest, _usd0.format(result.totalInterest),
                    highlight: false),
                _row2(tTotalCost, _usd0.format(result.totalCost), bold: true),
                _row2(tPayoffDate,
                    DateFormat('MMM yyyy').format(result.payoffDate)),
              ]),
              if (result.hasPmi) ...[
                pw.SizedBox(height: 10),
                _sectionBox(tPmi, [
                  _row2(tMonthlyPmi, _usd2.format(result.monthly.pmi)),
                  _row2(
                      tPmiDropsAt,
                      result.pmiDropMonth != null
                          ? '$tMonth ${result.pmiDropMonth} (${(result.pmiDropMonth! / 12).ceil()} yr)'
                          : '—'),
                  _row2('Note', tPmiNote, small: true),
                ]),
              ],
            ])),
            pw.SizedBox(width: 14),
            // Right column
            pw.Expanded(
                child: pw.Column(children: [
              _sectionBox(tMonthlyBreakdown, [
                _row2(tPandI, _usd2.format(result.monthly.piPayment),
                    bold: true, color: _navy),
                _row2(tPrincipal, _usd2.format(result.monthly.principal)),
                _row2(tInterest, _usd2.format(result.monthly.interest)),
                pw.Divider(color: PdfColors.grey300, height: 6),
                _row2(tPropertyTax, _usd2.format(result.monthly.propertyTax)),
                _row2(tHomeInsurance,
                    _usd2.format(result.monthly.homeInsurance)),
                if (input.hoaMonthly > 0)
                  _row2(tHoa, _usd2.format(result.monthly.hoa)),
                if (result.hasPmi)
                  _row2(tPmi, _usd2.format(result.monthly.pmi)),
                pw.Divider(color: PdfColors.grey300, height: 6),
                _row2(tTotal, _usd2.format(result.monthly.pitiPayment),
                    bold: true, color: _navy),
              ]),
              pw.SizedBox(height: 10),
              // ── Cost breakdown bar ──
              _costBar(result, isEs: isEs, label: tPrincipalVsInterest),
            ])),
          ],
        ),

        pw.SizedBox(height: 12),
        // ── Monthly payment donut chart ──
        _buildBreakdownChart(input, result, isEs: isEs),

        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Monthly payment breakdown donut chart ─────────────────────────────────

  static pw.Widget _buildBreakdownChart(
      MortgageInputState input, MortgageResult result,
      {bool isEs = false}) {
    final m = result.monthly;
    // Slice color palette (theme-coherent).
    const cPrincipal = _navy;
    const cInterest = _gold;
    const cTax = PdfColor(0.20, 0.55, 0.42); // green
    const cInsurance = PdfColor(0.40, 0.50, 0.78); // soft blue
    const cHoa = PdfColor(0.55, 0.40, 0.70); // purple
    const cPmi = PdfColor(0.78, 0.35, 0.35); // muted red

    // Real values from the calculated monthly breakdown.
    final slices = <_Slice>[
      _Slice(isEs ? 'Capital' : 'Principal', m.principal, cPrincipal),
      _Slice(isEs ? 'Interés' : 'Interest', m.interest, cInterest),
      _Slice(isEs ? 'Impuesto' : 'Property Tax', m.propertyTax, cTax),
      _Slice(isEs ? 'Seguro' : 'Insurance', m.homeInsurance, cInsurance),
      if (input.hoaMonthly > 0) _Slice('HOA', m.hoa, cHoa),
      if (result.hasPmi) _Slice('PMI', m.pmi, cPmi),
    ].where((s) => s.value > 0).toList();

    final total = slices.fold(0.0, (s, e) => s + e.value);
    final tTitle =
        isEs ? 'DESGLOSE DEL PAGO MENSUAL' : 'MONTHLY PAYMENT BREAKDOWN';

    return _sectionBox(tTitle, [
      pw.SizedBox(height: 6),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Donut
          pw.SizedBox(
            width: 150,
            height: 150,
            child: pw.Chart(
              grid: pw.PieGrid(),
              datasets: [
                for (final s in slices)
                  pw.PieDataSet(
                    value: s.value,
                    color: s.color,
                    legend: '',
                    innerRadius: 38,
                    surfaceOpacity: 1,
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          // Legend with real $ values + percentages
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final s in slices)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(children: [
                      pw.Container(width: 9, height: 9, color: s.color),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: pw.Text(s.label,
                            style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Text(
                        '${_usd2.format(s.value)}'
                        '  (${total > 0 ? (s.value / total * 100).toStringAsFixed(0) : '0'}%)',
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    ]);
  }

  // ── Cost breakdown visual bar ─────────────────────────────────────────────

  static pw.Widget _costBar(MortgageResult result,
      {bool isEs = false, String? label}) {
    final total = result.totalCost;
    final loanPct = total > 0 ? result.loanAmount / total : 0.0;
    final intPct = total > 0 ? result.totalInterest / total : 0.0;
    final tPrincipal = isEs ? 'Capital' : 'Principal';
    final tInterest = isEs ? 'Interés' : 'Interest';
    return _sectionBox(label ?? (isEs ? 'CAPITAL vs INTERÉS' : 'PRINCIPAL vs INTEREST'), [
      pw.SizedBox(height: 6),
      pw.Row(children: [
        pw.Expanded(
          flex: (loanPct * 100).round(),
          child: pw.Container(
              height: 14,
              color: _navy,
              child: pw.Center(
                  child: pw.Text(
                '${(loanPct * 100).toStringAsFixed(0)}%',
                style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold),
              ))),
        ),
        pw.Expanded(
          flex: max(1, (intPct * 100).round()),
          child: pw.Container(
              height: 14,
              color: _gold,
              child: pw.Center(
                  child: pw.Text(
                '${(intPct * 100).toStringAsFixed(0)}%',
                style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold),
              ))),
        ),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Row(children: [
          pw.Container(width: 8, height: 8, color: _navy),
          pw.SizedBox(width: 4),
          pw.Text('$tPrincipal: ${_usd0.format(result.loanAmount)}',
              style: const pw.TextStyle(fontSize: 8)),
        ]),
        pw.Row(children: [
          pw.Container(width: 8, height: 8, color: _gold),
          pw.SizedBox(width: 4),
          pw.Text('$tInterest: ${_usd0.format(result.totalInterest)}',
              style: const pw.TextStyle(fontSize: 8)),
        ]),
      ]),
    ]);
  }

  // ── Yearly amortization section ───────────────────────────────────────────

  static List<pw.Widget> _buildYearlySection(MortgageResult result,
      {bool isEs = false}) {
    final schedule = result.schedule;
    final yearlyData = <List<String>>[];
    final tYear = isEs ? 'Año' : 'Year';

    final totalYears = (schedule.length / 12.0).ceil();
    for (int yr = 1; yr <= totalYears; yr++) {
      final start = (yr - 1) * 12;
      final end = min(yr * 12, schedule.length);
      final slice = schedule.sublist(start, end);

      final annualPmt = slice.fold(0.0, (s, e) => s + e.payment);
      final annualPrin = slice.fold(0.0, (s, e) => s + e.principal);
      final annualInt = slice.fold(0.0, (s, e) => s + e.interest);
      final endBal = slice.last.balance;
      final cumInt = slice.last.cumulativeInterest;

      yearlyData.add([
        '$tYear $yr',
        _usd0.format(annualPmt),
        _usd0.format(annualPrin),
        _usd0.format(annualInt),
        _usd0.format(endBal),
        _usd0.format(cumInt),
      ]);
    }

    return [
      _tableTitle(isEs
          ? 'RESUMEN DE AMORTIZACIÓN ANUAL'
          : 'YEARLY AMORTIZATION SUMMARY'),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: [
          isEs ? 'Año' : 'Year',
          isEs ? 'Pago total' : 'Total Pmt',
          isEs ? 'Capital' : 'Principal',
          isEs ? 'Interés' : 'Interest',
          isEs ? 'Saldo' : 'Balance',
          isEs ? 'Int. acum.' : 'Cum. Interest'
        ],
        data: yearlyData,
        headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _navy),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellHeight: 14,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
        },
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: pw.BoxDecoration(color: _light),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(48),
          1: const pw.FlexColumnWidth(),
          2: const pw.FlexColumnWidth(),
          3: const pw.FlexColumnWidth(),
          4: const pw.FlexColumnWidth(),
          5: const pw.FlexColumnWidth(),
        },
      ),
    ];
  }

  // ── Monthly amortization section ──────────────────────────────────────────

  static List<pw.Widget> _buildMonthlySection(MortgageResult result,
      {bool isEs = false}) {
    final rows = result.schedule
        .map((e) => [
              e.month.toString(),
              _dateShort.format(e.date),
              _usd0.format(e.payment),
              _usd0.format(e.principal),
              _usd0.format(e.interest),
              e.pmiAmount > 0 ? _usd0.format(e.pmiAmount) : '—',
              _usd0.format(e.balance),
              _usd0.format(e.cumulativeInterest),
            ])
        .toList();

    return [
      _tableTitle(isEs
          ? 'TABLA DE AMORTIZACIÓN MENSUAL COMPLETA'
          : 'FULL MONTHLY AMORTIZATION SCHEDULE'),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: [
          isEs ? 'Mes' : 'Mo.',
          isEs ? 'Fecha' : 'Date',
          isEs ? 'Pago' : 'Payment',
          isEs ? 'Capital' : 'Principal',
          isEs ? 'Interés' : 'Interest',
          'PMI',
          isEs ? 'Saldo' : 'Balance',
          isEs ? 'Int. acum.' : 'Cum. Int.'
        ],
        data: rows,
        headerStyle: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _navy),
        cellStyle: const pw.TextStyle(fontSize: 7),
        cellHeight: 12,
        cellAlignments: {
          0: pw.Alignment.center,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
          7: pw.Alignment.centerRight,
        },
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: pw.BoxDecoration(color: _light),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
        columnWidths: {
          0: const pw.FixedColumnWidth(22),
          1: const pw.FixedColumnWidth(38),
          2: const pw.FlexColumnWidth(),
          3: const pw.FlexColumnWidth(),
          4: const pw.FlexColumnWidth(),
          5: const pw.FlexColumnWidth(),
          6: const pw.FlexColumnWidth(),
          7: const pw.FlexColumnWidth(),
        },
      ),
    ];
  }

  // ── Amortization page header ──────────────────────────────────────────────

  static pw.Widget _amortHeader(
          MortgageInputState input, MortgageResult result, int page,
          {bool isEs = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 0.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                isEs
                    ? 'MortgageUS — Tabla de Amortización'
                    : 'MortgageUS — Amortization Schedule',
                style: pw.TextStyle(
                    fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.Text(
              '${_usd0.format(input.homePrice)} · '
              '${input.annualRatePct.toStringAsFixed(2)}% · '
              '${input.termYears}${isEs ? 'a' : 'yr'} · '
              '${input.loanType.label}'
              '  |  ${isEs ? 'Pág.' : 'Page'} $page',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      );

  // ── Footer ────────────────────────────────────────────────────────────────

  static pw.Widget _footer(pw.Context ctx, {bool isEs = false}) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
            border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                isEs
                    ? 'Solo para ilustración. No es asesoramiento financiero.'
                    : 'For illustration purposes only. Not financial advice.',
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
            pw.Text(
                '${isEs ? 'Pág.' : 'Page'} ${ctx.pageNumber} ${isEs ? 'de' : 'of'} ${ctx.pagesCount}',
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          ],
        ),
      );

  static pw.Widget _footerNote({bool isEs = false}) => pw.Column(children: [
        pw.Divider(color: PdfColors.grey300, height: 12),
        pw.Text(
          isEs
              ? 'Generado por MortgageUS · Solo para ilustración. No es asesoramiento financiero.'
              : 'Generated by MortgageUS · For illustration purposes only. Not financial advice.',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ]);

  // ── Small helpers ─────────────────────────────────────────────────────────

  static pw.Widget _tableTitle(String text) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: _navy,
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white)),
      );

  static pw.Widget _sectionBox(String title, List<pw.Widget> rows) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: _navy,
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(AppSpacing.sm),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
            child: pw.Column(children: rows),
          ),
        ],
      );

  static pw.Widget _row2(
    String label,
    String value, {
    bool bold = false,
    bool highlight = false,
    bool small = false,
    PdfColor? color,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: small ? 8 : 9,
                    color: small ? PdfColors.grey600 : PdfColors.grey800)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: small ? 8 : 9,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: highlight ? _gold : (color ?? PdfColors.black))),
          ],
        ),
      );

  // ── Unlock sheet entry point (unchanged) ─────────────────────────────────

  /// Shows a bottom sheet: "Watch video (unlock once)" or "Get Premium $2.99".
  static Future<void> showUnlockOrPay(
    BuildContext context,
    Future<void> Function() onExport,
  ) async {
    final isEs = isSpanishNotifier.value;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PdfUnlockSheet(isEs: isEs, onExport: onExport),
    );
  }
}

// ── Donut chart slice model ───────────────────────────────────────────────────

class _Slice {
  final String label;
  final double value;
  final PdfColor color;
  const _Slice(this.label, this.value, this.color);
}

// ── PDF unlock bottom sheet ───────────────────────────────────────────────────

class _PdfUnlockSheet extends StatefulWidget {
  final bool isEs;
  final Future<void> Function() onExport;
  const _PdfUnlockSheet({required this.isEs, required this.onExport});

  @override
  State<_PdfUnlockSheet> createState() => _PdfUnlockSheetState();
}

class _PdfUnlockSheetState extends State<_PdfUnlockSheet> {
  bool _loading = false;

  Future<void> _watchAd() async {
    setState(() => _loading = true);
    final earned = await adService.showRewarded();
    if (!mounted) return;
    setState(() => _loading = false);
    if (earned) {
      Navigator.pop(context);
      await widget.onExport();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.isEs
            ? 'Anuncio no disponible. Inténtalo más tarde.'
            : 'Ad not available. Try again later.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    final adReady = adService.isRewardedReady;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.picture_as_pdf_rounded,
              size: 36, color: AppTheme.primary),
          const SizedBox(height: 12),
          Text(
            isEs ? 'Exportar PDF' : 'Export PDF',
            style: const TextStyle(
                fontSize: AppTextSize.subtitle, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            isEs
                ? 'Elige cómo desbloquear la exportación'
                : 'Choose how to unlock PDF export',
            style: TextStyle(
                fontSize: AppTextSize.md,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 24),
          // Option 1: Watch ad (once)
          Opacity(
            opacity: adReady ? 1.0 : 0.45,
            child: InkWell(
              onTap: (adReady && !_loading) ? _watchAd : null,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_circle_outline,
                          color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEs ? 'Ver un video corto' : 'Watch a short video',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: AppTextSize.bodyMd),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEs
                                ? 'Exportar una vez — gratis'
                                : 'Export once — free',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.65),
                                fontSize: AppTextSize.md),
                          ),
                        ],
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Option 2: Get Premium
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                IAPService.instance.buy();
              },
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text(
                isEs
                    ? 'Premium — \$4.99 (ilimitado)'
                    : 'Premium — \$4.99 (unlimited)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isEs ? 'Ahora no' : 'Not now',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65))),
          ),
        ],
      ),
    );
  }
}

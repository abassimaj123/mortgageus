import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../presentation/providers/mortgage_providers.dart';
import '../../domain/models/mortgage_result.dart';
import '../../domain/models/loan_type.dart';
import '../../domain/models/extra_payment_result.dart';
import '../../domain/models/refinance_result.dart';
import '../../domain/models/affordability_result.dart';
import '../../domain/models/arm_result.dart';
import '../theme/app_theme.dart';
import '../../main.dart' show adService, isSpanishNotifier;
import '../freemium/freemium_service.dart' show freemiumService;
import '../../presentation/widgets/paywall_hard.dart';
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

// ── Isolate params classes ─────────────────────────────────────────────────
// All fields must be sendable between isolates:
// ✅ String, int, double, bool, null, DateTime, enum
// ✅ List<T>, Map<K,V> where T,K,V are sendable
// ✅ Plain Dart data classes with only sendable fields

class _MortgagePdfParams {
  final MortgageInputState input;
  final MortgageResult result;
  final bool isEs;
  const _MortgagePdfParams({required this.input, required this.result, required this.isEs});
}

class _ComparatorPdfParams {
  final MortgageInputState input;
  final MortgageResult r30;
  final MortgageResult r15;
  final bool isEs;
  const _ComparatorPdfParams({required this.input, required this.r30, required this.r15, required this.isEs});
}

class _ExtraPaymentsPdfParams {
  final MortgageInputState input;
  final ExtraPaymentResult result;
  final double extraMonthly;
  final double extraAnnual;
  final double lumpSum;
  final bool isEs;
  const _ExtraPaymentsPdfParams({
    required this.input, required this.result,
    required this.extraMonthly, required this.extraAnnual,
    required this.lumpSum, required this.isEs,
  });
}

class _RefinancePdfParams {
  final double balance;
  final double curRate;
  final int curYears;
  final double newRate;
  final int newYears;
  final double closing;
  final RefinanceResult result;
  final bool isEs;
  const _RefinancePdfParams({
    required this.balance, required this.curRate, required this.curYears,
    required this.newRate, required this.newYears, required this.closing,
    required this.result, required this.isEs,
  });
}

class _InvestmentReturnPdfParams {
  final double price;
  final double downPct;
  final double rent;
  final double appreciation;
  final int holdYears;
  final double rate;
  final double downAmt;
  final double initialInv;
  final double loanAmt;
  final double mortgageMo;
  final double monthlyCF;
  final double cashOnCash;
  final double irr;
  final double npv;
  final double equityMult;
  final bool isEs;
  const _InvestmentReturnPdfParams({
    required this.price, required this.downPct, required this.rent,
    required this.appreciation, required this.holdYears, required this.rate,
    required this.downAmt, required this.initialInv, required this.loanAmt,
    required this.mortgageMo, required this.monthlyCF, required this.cashOnCash,
    required this.irr, required this.npv, required this.equityMult, required this.isEs,
  });
}

class _PmiCalculatorPdfParams {
  final double homePrice;
  final double downPct;
  final double loanAmount;
  final double ltv;
  final int creditScore;
  final double pmiAnnualRate;
  final double monthlyPmi;
  final int? monthsTo80;
  final int? monthsTo78;
  final double rate;
  final bool isEs;
  const _PmiCalculatorPdfParams({
    required this.homePrice, required this.downPct, required this.loanAmount,
    required this.ltv, required this.creditScore, required this.pmiAnnualRate,
    required this.monthlyPmi, required this.monthsTo80, required this.monthsTo78,
    required this.rate, required this.isEs,
  });
}

class _PointsPdfParams {
  final double loanAmount;
  final double origRate;
  final double points;
  final int termYears;
  final double newRate;
  final double pointsCost;
  final double origPayment;
  final double newPayment;
  final double monthlySavings;
  final double? breakevenMonths;
  final double lifetimeSavings;
  final bool isEs;
  const _PointsPdfParams({
    required this.loanAmount, required this.origRate, required this.points,
    required this.termYears, required this.newRate, required this.pointsCost,
    required this.origPayment, required this.newPayment,
    required this.monthlySavings, required this.breakevenMonths,
    required this.lifetimeSavings, required this.isEs,
  });
}

class _UsdaPdfParams {
  final double homePrice;
  final double income;
  final double rate;
  final int termYears;
  final bool ruralEligible;
  final bool incomeOk;
  final double maxIncome;
  final double upfrontFee;
  final double loanAmount;
  final double monthlyAnnualFee;
  final double pAndI;
  final double propertyTax;
  final double insurance;
  final double totalMonthly;
  final bool isEs;
  const _UsdaPdfParams({
    required this.homePrice, required this.income, required this.rate,
    required this.termYears, required this.ruralEligible, required this.incomeOk,
    required this.maxIncome, required this.upfrontFee, required this.loanAmount,
    required this.monthlyAnnualFee, required this.pAndI, required this.propertyTax,
    required this.insurance, required this.totalMonthly, required this.isEs,
  });
}

class _VaPdfParams {
  final double homePrice;
  final double downPct;
  final double downAmt;
  final double ffRate;
  final double fundingFee;
  final double loanAmount;
  final double rate;
  final int termYears;
  final bool reserves;
  final bool subsequent;
  final double pAndI;
  final double propertyTax;
  final double insurance;
  final double totalMonthly;
  final bool isEs;
  const _VaPdfParams({
    required this.homePrice, required this.downPct, required this.downAmt,
    required this.ffRate, required this.fundingFee, required this.loanAmount,
    required this.rate, required this.termYears, required this.reserves,
    required this.subsequent, required this.pAndI, required this.propertyTax,
    required this.insurance, required this.totalMonthly, required this.isEs,
  });
}

class _AffordabilityPdfParams {
  final double annualIncome;
  final double monthlyDebts;
  final double downPayment;
  final double annualRatePct;
  final int termYears;
  final double propertyTaxRatePct;
  final double homeInsuranceAnnual;
  final double hoaMonthly;
  final AffordabilityResult result;
  final bool isEs;
  const _AffordabilityPdfParams({
    required this.annualIncome, required this.monthlyDebts, required this.downPayment,
    required this.annualRatePct, required this.termYears,
    required this.propertyTaxRatePct, required this.homeInsuranceAnnual, required this.hoaMonthly,
    required this.result, required this.isEs,
  });
}

class _ArmPdfParams {
  final double loanAmount;
  final double initialRatePct;
  final int fixedYears;
  final double adjustedRatePct;
  final int termYears;
  final ARMResult result;
  final bool isEs;
  const _ArmPdfParams({
    required this.loanAmount, required this.initialRatePct, required this.fixedYears,
    required this.adjustedRatePct, required this.termYears,
    required this.result, required this.isEs,
  });
}

class _ClosingCostsPdfParams {
  final double homePrice;
  final String state;
  final String loanType;
  final bool isBuyer;
  final List<Map<String, dynamic>> lineItems;
  final double total;
  final bool isEs;
  const _ClosingCostsPdfParams({
    required this.homePrice, required this.state, required this.loanType,
    required this.isBuyer, required this.lineItems, required this.total, required this.isEs,
  });
}

class _DtiPdfParams {
  final double annualIncome;
  final double piti;
  final double carPayment;
  final double studentLoans;
  final double creditCards;
  final double otherDebts;
  final double frontEndDti;
  final double backEndDti;
  final bool isEs;
  const _DtiPdfParams({
    required this.annualIncome, required this.piti, required this.carPayment,
    required this.studentLoans, required this.creditCards, required this.otherDebts,
    required this.frontEndDti, required this.backEndDti, required this.isEs,
  });
}

class _FhaPdfParams {
  final double homePrice;
  final double downPct;
  final double annualRatePct;
  final int termYears;
  final int creditScore;
  final double baseLoan;
  final double upfrontMip;
  final double loan;
  final double annualMipRate;
  final double monthlyMip;
  final double pAndI;
  final double monthlyTax;
  final double monthlyIns;
  final double totalMonthly;
  final bool isEs;
  const _FhaPdfParams({
    required this.homePrice, required this.downPct, required this.annualRatePct,
    required this.termYears, required this.creditScore, required this.baseLoan,
    required this.upfrontMip, required this.loan, required this.annualMipRate,
    required this.monthlyMip, required this.pAndI, required this.monthlyTax,
    required this.monthlyIns, required this.totalMonthly, required this.isEs,
  });
}

class _HelocPdfParams {
  final double homeValue;
  final double mortgageBalance;
  final double maxLtv;
  final double drawAmount;
  final double rate;
  final int drawPeriod;
  final int repaymentPeriod;
  final double availableEquity;
  final double monthlyInterestOnly;
  final double monthlyRepayment;
  final double totalCost;
  final bool isEs;
  const _HelocPdfParams({
    required this.homeValue, required this.mortgageBalance, required this.maxLtv,
    required this.drawAmount, required this.rate, required this.drawPeriod,
    required this.repaymentPeriod, required this.availableEquity,
    required this.monthlyInterestOnly, required this.monthlyRepayment,
    required this.totalCost, required this.isEs,
  });
}

class _PmiSimplePdfParams {
  final double homePrice;
  final double downPct;
  final double loanAmount;
  final double ltv;
  final double monthlyPmi;
  final int? dropMonth;
  final double totalPmiCost;
  final bool isEs;
  const _PmiSimplePdfParams({
    required this.homePrice, required this.downPct, required this.loanAmount,
    required this.ltv, required this.monthlyPmi, required this.dropMonth,
    required this.totalPmiCost, required this.isEs,
  });
}

// ── Top-level isolate builder functions ────────────────────────────────────
// These are top-level so they can be passed to Isolate.run().
// They call private static methods on PdfExportService (file-private in Dart).

Future<Uint8List> _buildMortgagePdf(_MortgagePdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildSummaryPage(p.input, p.result, isEs: p.isEs),
  ));
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
    header: (ctx) => PdfExportService._amortHeader(p.input, p.result, ctx.pageNumber, isEs: p.isEs),
    footer: (ctx) => PdfExportService._footer(ctx, isEs: p.isEs),
    build: (_) => [
      ...PdfExportService._buildYearlySection(p.result, isEs: p.isEs),
      pw.SizedBox(height: 18),
      ...PdfExportService._buildMonthlySection(p.result, isEs: p.isEs),
    ],
  ));
  return await pdf.save();
}

Future<Uint8List> _buildComparatorPdf(_ComparatorPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildComparatorPage(p.input, p.r30, p.r15, isEs: p.isEs),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildExtraPaymentsPdf(_ExtraPaymentsPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildExtraPaymentsPage(
      p.input, p.result,
      extraMonthly: p.extraMonthly, extraAnnual: p.extraAnnual,
      lumpSum: p.lumpSum, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildRefinancePdf(_RefinancePdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildRefinancePage(
      balance: p.balance, curRate: p.curRate, curYears: p.curYears,
      newRate: p.newRate, newYears: p.newYears, closing: p.closing,
      result: p.result, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildInvestmentReturnPdf(_InvestmentReturnPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildInvestmentReturnPage(
      price: p.price, downPct: p.downPct, rent: p.rent,
      appreciation: p.appreciation, holdYears: p.holdYears, rate: p.rate,
      downAmt: p.downAmt, initialInv: p.initialInv, loanAmt: p.loanAmt,
      mortgageMo: p.mortgageMo, monthlyCF: p.monthlyCF, cashOnCash: p.cashOnCash,
      irr: p.irr, npv: p.npv, equityMult: p.equityMult, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildPmiCalculatorPdf(_PmiCalculatorPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildPmiCalculatorPage(
      homePrice: p.homePrice, downPct: p.downPct, loanAmount: p.loanAmount,
      ltv: p.ltv, creditScore: p.creditScore, pmiAnnualRate: p.pmiAnnualRate,
      monthlyPmi: p.monthlyPmi, monthsTo80: p.monthsTo80, monthsTo78: p.monthsTo78,
      rate: p.rate, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildPointsPdf(_PointsPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildPointsPage(
      loanAmount: p.loanAmount, origRate: p.origRate, points: p.points,
      termYears: p.termYears, newRate: p.newRate, pointsCost: p.pointsCost,
      origPayment: p.origPayment, newPayment: p.newPayment,
      monthlySavings: p.monthlySavings, breakevenMonths: p.breakevenMonths,
      lifetimeSavings: p.lifetimeSavings, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildUsdaPdf(_UsdaPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildUsdaPage(
      homePrice: p.homePrice, income: p.income, rate: p.rate,
      termYears: p.termYears, ruralEligible: p.ruralEligible, incomeOk: p.incomeOk,
      maxIncome: p.maxIncome, upfrontFee: p.upfrontFee, loanAmount: p.loanAmount,
      monthlyAnnualFee: p.monthlyAnnualFee, pAndI: p.pAndI,
      propertyTax: p.propertyTax, insurance: p.insurance,
      totalMonthly: p.totalMonthly, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildVaPdf(_VaPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildVaPage(
      homePrice: p.homePrice, downPct: p.downPct, downAmt: p.downAmt,
      ffRate: p.ffRate, fundingFee: p.fundingFee, loanAmount: p.loanAmount,
      rate: p.rate, termYears: p.termYears, reserves: p.reserves,
      subsequent: p.subsequent, pAndI: p.pAndI, propertyTax: p.propertyTax,
      insurance: p.insurance, totalMonthly: p.totalMonthly, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildAffordabilityPdf(_AffordabilityPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildAffordabilityPage(
      annualIncome: p.annualIncome, monthlyDebts: p.monthlyDebts,
      downPayment: p.downPayment, annualRatePct: p.annualRatePct,
      termYears: p.termYears,
      propertyTaxRatePct: p.propertyTaxRatePct,
      homeInsuranceAnnual: p.homeInsuranceAnnual,
      hoaMonthly: p.hoaMonthly,
      result: p.result, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildArmPdf(_ArmPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildArmPage(
      loanAmount: p.loanAmount, initialRatePct: p.initialRatePct,
      fixedYears: p.fixedYears, adjustedRatePct: p.adjustedRatePct,
      termYears: p.termYears, result: p.result, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildClosingCostsPdf(_ClosingCostsPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildClosingCostsPage(
      homePrice: p.homePrice, state: p.state, loanType: p.loanType,
      isBuyer: p.isBuyer, lineItems: p.lineItems, total: p.total, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildDtiPdf(_DtiPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildDtiPage(
      annualIncome: p.annualIncome, piti: p.piti, carPayment: p.carPayment,
      studentLoans: p.studentLoans, creditCards: p.creditCards,
      otherDebts: p.otherDebts, frontEndDti: p.frontEndDti,
      backEndDti: p.backEndDti, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildFhaPdf(_FhaPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildFhaPage(
      homePrice: p.homePrice, downPct: p.downPct, annualRatePct: p.annualRatePct,
      termYears: p.termYears, creditScore: p.creditScore, baseLoan: p.baseLoan,
      upfrontMip: p.upfrontMip, loan: p.loan, annualMipRate: p.annualMipRate,
      monthlyMip: p.monthlyMip, pAndI: p.pAndI, monthlyTax: p.monthlyTax,
      monthlyIns: p.monthlyIns, totalMonthly: p.totalMonthly, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildHelocPdf(_HelocPdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildHelocPage(
      homeValue: p.homeValue, mortgageBalance: p.mortgageBalance, maxLtv: p.maxLtv,
      drawAmount: p.drawAmount, rate: p.rate, drawPeriod: p.drawPeriod,
      repaymentPeriod: p.repaymentPeriod, availableEquity: p.availableEquity,
      monthlyInterestOnly: p.monthlyInterestOnly, monthlyRepayment: p.monthlyRepayment,
      totalCost: p.totalCost, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildPmiSimplePdf(_PmiSimplePdfParams p) async {
  await initializeDateFormatting();
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (_) => PdfExportService._buildPmiSimplePage(
      homePrice: p.homePrice, downPct: p.downPct, loanAmount: p.loanAmount,
      ltv: p.ltv, monthlyPmi: p.monthlyPmi, dropMonth: p.dropMonth,
      totalPmiCost: p.totalPmiCost, isEs: p.isEs,
    ),
  ));
  return await pdf.save();
}

class PdfExportService {
  static final _usd2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  static final _usd0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  static DateFormat _dateLong(bool isEs) => DateFormat('MMMM d, yyyy', isEs ? 'es' : 'en');
  static DateFormat _dateShort(bool isEs) => DateFormat('MMM yy', isEs ? 'es' : 'en');

  // ── Public entry point ────────────────────────────────────────────────────

  static Future<void> exportMortgage(
    BuildContext context,
    MortgageInputState input,
    MortgageResult result, {
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildMortgagePdf(_MortgagePdfParams(input: input, result: result, isEs: isEs)),
    );
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
            pw.Text(_dateLong(isEs).format(now),
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
                _row2(tLoanType, isEs ? _loanTypeEs(input.loanType) : input.loanType.label),
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
                    DateFormat('MMM yyyy', isEs ? 'es' : 'en')
                        .format(result.payoffDate)),
              ]),
              if (result.hasPmi) ...[
                pw.SizedBox(height: 10),
                _sectionBox(tPmi, [
                  _row2(tMonthlyPmi, _usd2.format(result.monthly.pmi)),
                  _row2(
                      tPmiDropsAt,
                      result.pmiDropMonth != null
                          ? '$tMonth ${result.pmiDropMonth} (${(result.pmiDropMonth! / 12).ceil()} ${(result.pmiDropMonth! / 12).ceil() == 1 ? (isEs ? 'año' : 'year') : (isEs ? 'años' : 'years')})'
                          : '-'),
                  _row2(isEs ? 'Nota' : 'Note', tPmiNote, small: true),
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
              _dateShort(isEs).format(e.date),
              _usd0.format(e.payment),
              _usd0.format(e.principal),
              _usd0.format(e.interest),
              e.pmiAmount > 0 ? _usd0.format(e.pmiAmount) : '-',
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
                    ? 'MortgageUS - Tabla de Amortización'
                    : 'MortgageUS - Amortization Schedule',
                style: pw.TextStyle(
                    fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.Text(
              '${_usd0.format(input.homePrice)} · '
              '${input.annualRatePct.toStringAsFixed(2)}% · '
              '${input.termYears}${isEs ? 'a' : 'yr'} · '
              '${isEs ? _loanTypeEs(input.loanType) : input.loanType.label}'
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

  static String _loanTypeEs(LoanType t) {
    switch (t) {
      case LoanType.conventional:
        return 'Convencional';
      default:
        return t.label; // FHA, VA, Jumbo, USDA same in ES
    }
  }

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

  // ── Comparator PDF export ─────────────────────────────────────────────────

  static Future<void> exportComparator(
    BuildContext context,
    MortgageInputState input,
    MortgageResult r30,
    MortgageResult r15, {
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildComparatorPdf(_ComparatorPdfParams(input: input, r30: r30, r15: r15, isEs: isEs)),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_Comparator_${input.homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildComparatorPage(
      MortgageInputState input, MortgageResult r30, MortgageResult r15,
      {bool isEs = false}) {
    final now = DateTime.now();
    final tReport = isEs ? 'Comparación 15 vs 30 años' : '15 vs 30 Year Comparison';
    final tLoanInfo = isEs ? 'INFORMACIÓN DEL PRÉSTAMO' : 'LOAN INFORMATION';
    final tHomePrice = isEs ? 'Precio de la casa' : 'Home Price';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tInterestRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tComparison = isEs ? 'COMPARACIÓN 15 vs 30 AÑOS' : '15 VS 30 YEAR COMPARISON';
    final tMetric = isEs ? 'Métrica' : 'Metric';
    final t30yr = isEs ? '30 años' : '30 Year';
    final t15yr = isEs ? '15 años' : '15 Year';
    final tMonthlyPI = isEs ? 'Pago mensual (P&I)' : 'Monthly P&I';
    final tTotalInterest = isEs ? 'Interés total' : 'Total Interest';
    final tTotalCost = isEs ? 'Costo total' : 'Total Cost';
    final tPayoff = isEs ? 'Fecha pago final' : 'Payoff Date';
    final tAdvantage = isEs ? 'VENTAJA 15 AÑOS' : '15-YEAR ADVANTAGE';
    final tInterestSaved = isEs ? 'Interés ahorrado' : 'Interest saved';
    final tPaidOffEarlier = isEs ? 'Pagado antes' : 'Paid off earlier';
    final tYears = isEs ? 'años' : 'years';

    final yearsDiff = r30.payoffDate.year - r15.payoffDate.year;
    final interestSaved = r30.totalInterest - r15.totalInterest;
    final extraMonthly = r15.monthly.piPayment - r30.monthly.piPayment;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(
                      fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        _sectionBox(tLoanInfo, [
          _row2(tHomePrice, _usd0.format(input.homePrice)),
          _row2(tLoanAmount, _usd0.format(r30.loanAmount)),
          _row2(tInterestRate, '${input.annualRatePct.toStringAsFixed(2)}%'),
        ]),
        pw.SizedBox(height: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: _navy,
              child: pw.Text(tComparison,
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(AppSpacing.sm),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
              child: pw.TableHelper.fromTextArray(
                headers: [tMetric, t30yr, t15yr],
                data: [
                  [tMonthlyPI, _usd2.format(r30.monthly.piPayment), _usd2.format(r15.monthly.piPayment)],
                  [tTotalInterest, _usd0.format(r30.totalInterest), _usd0.format(r15.totalInterest)],
                  [tTotalCost, _usd0.format(r30.totalCost), _usd0.format(r15.totalCost)],
                  [tPayoff,
                    '${r30.payoffDate.month}/${r30.payoffDate.year}',
                    '${r15.payoffDate.month}/${r15.payoffDate.year}'],
                ],
                headerStyle: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: _navy),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellHeight: 16,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        _sectionBox(tAdvantage, [
          _row2(tInterestSaved, _usd0.format(interestSaved),
              bold: true, color: PdfColor(0.13, 0.55, 0.33)),
          _row2(tPaidOffEarlier, '$yearsDiff $tYears',
              bold: true, color: PdfColor(0.13, 0.55, 0.33)),
          _row2(
            isEs ? 'Pago mensual adicional (15 años)' : 'Extra monthly payment (15yr)',
            _usd2.format(extraMonthly),
          ),
        ]),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Extra Payments PDF export ─────────────────────────────────────────────

  static Future<void> exportExtraPayments(
    BuildContext context,
    MortgageInputState input,
    ExtraPaymentResult result, {
    required double extraMonthly,
    required double extraAnnual,
    required double lumpSum,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildExtraPaymentsPdf(_ExtraPaymentsPdfParams(
        input: input, result: result,
        extraMonthly: extraMonthly, extraAnnual: extraAnnual,
        lumpSum: lumpSum, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final loan = input.homePrice - input.downPaymentDollar;
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_ExtraPayments_${loan.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildExtraPaymentsPage(
      MortgageInputState input, ExtraPaymentResult result, {
      required double extraMonthly,
      required double extraAnnual,
      required double lumpSum,
      bool isEs = false}) {
    final now = DateTime.now();
    final loan = input.homePrice - input.downPaymentDollar;
    final tReport = isEs ? 'Simulación de Pagos Extra' : 'Extra Payments Simulation';
    final tLoanInfo = isEs ? 'PRÉSTAMO BASE' : 'BASE LOAN';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tInterestRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tLoanTerm = isEs ? 'Plazo' : 'Loan Term';
    final tYears = isEs ? 'años' : 'years';
    final tExtraPayments = isEs ? 'PAGOS ADICIONALES' : 'EXTRA PAYMENTS';
    final tExtraMonthly = isEs ? 'Extra mensual' : 'Monthly extra';
    final tExtraAnnual = isEs ? 'Extra anual' : 'Annual extra';
    final tLumpSum = isEs ? 'Pago único' : 'Lump sum';
    final tResults = isEs ? 'RESULTADOS' : 'RESULTS';
    final tOrigPayoff = isEs ? 'Pago original (meses)' : 'Original payoff (months)';
    final tNewPayoff = isEs ? 'Nuevo pago (meses)' : 'New payoff (months)';
    final tTimeSaved = isEs ? 'Tiempo ahorrado' : 'Time saved';
    final tOrigInterest = isEs ? 'Interés total original' : 'Original total interest';
    final tNewInterest = isEs ? 'Nuevo interés total' : 'New total interest';
    final tInterestSaved = isEs ? 'Interés ahorrado' : 'Interest saved';
    final months = isEs ? 'meses' : 'months';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(
                      fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tLoanInfo, [
                  _row2(tLoanAmount, _usd0.format(loan)),
                  _row2(tInterestRate, '${input.annualRatePct.toStringAsFixed(2)}%'),
                  _row2(tLoanTerm, '${input.termYears} $tYears'),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tExtraPayments, [
                  if (extraMonthly > 0)
                    _row2(tExtraMonthly, _usd2.format(extraMonthly)),
                  if (extraAnnual > 0)
                    _row2(tExtraAnnual, _usd2.format(extraAnnual)),
                  if (lumpSum > 0)
                    _row2(tLumpSum, _usd2.format(lumpSum)),
                  if (extraMonthly == 0 && extraAnnual == 0 && lumpSum == 0)
                    _row2(isEs ? 'Ninguno' : 'None', '-'),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _sectionBox(tResults, [
                _row2(tOrigPayoff, '${result.originalPayoffMonths} $months'),
                _row2(tNewPayoff, '${result.newPayoffMonths} $months'),
                _row2(tTimeSaved,
                    '${result.yearsSaved} $tYears ${result.remMonthsSaved} $months',
                    bold: true, color: PdfColor(0.13, 0.55, 0.33)),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Divider(color: PdfColors.grey300, height: 6),
                ),
                _row2(tOrigInterest, _usd0.format(result.originalTotalInterest)),
                _row2(tNewInterest, _usd0.format(result.newTotalInterest)),
                _row2(tInterestSaved, _usd0.format(result.interestSaved),
                    bold: true, color: PdfColor(0.13, 0.55, 0.33)),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Refinance PDF export ──────────────────────────────────────────────────

  static Future<void> exportRefinance(
    BuildContext context, {
    required double balance,
    required double curRate,
    required int curYears,
    required double newRate,
    required int newYears,
    required double closing,
    required RefinanceResult result,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildRefinancePdf(_RefinancePdfParams(
        balance: balance, curRate: curRate, curYears: curYears,
        newRate: newRate, newYears: newYears, closing: closing,
        result: result, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_Refinance_${balance.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildRefinancePage({
    required double balance,
    required double curRate,
    required int curYears,
    required double newRate,
    required int newYears,
    required double closing,
    required RefinanceResult result,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Análisis de Refinanciamiento' : 'Refinance Analysis';
    final tCurrent = isEs ? 'PRÉSTAMO ACTUAL' : 'CURRENT LOAN';
    final tNew = isEs ? 'NUEVO PRÉSTAMO' : 'NEW LOAN';
    final tResults = isEs ? 'RESULTADOS' : 'RESULTS';
    final tBalance = isEs ? 'Saldo actual' : 'Current balance';
    final tCurRate = isEs ? 'Tasa actual' : 'Current rate';
    final tCurTerm = isEs ? 'Años restantes' : 'Years remaining';
    final tNewRate = isEs ? 'Nueva tasa' : 'New rate';
    final tNewTerm = isEs ? 'Nuevo plazo' : 'New term';
    final tClosing = isEs ? 'Costos de cierre' : 'Closing costs';
    final tCurPayment = isEs ? 'Pago actual' : 'Current payment';
    final tNewPayment = isEs ? 'Nuevo pago' : 'New payment';
    final tMonthlySavings = isEs ? 'Ahorro mensual' : 'Monthly savings';
    final tBreakEven = isEs ? 'Punto de equilibrio' : 'Break-even';
    final tTotalSavings =
        isEs ? 'Ahorro total (vida del préstamo)' : 'Lifetime savings';
    final tYears = isEs ? 'años' : 'years';
    final tMonths = isEs ? 'meses' : 'months';
    final tRecommendation = isEs ? 'RECOMENDACIÓN' : 'RECOMMENDATION';

    final breakEvenText = result.monthlySavings <= 0
        ? (isEs ? 'N/A - tasa más alta' : 'N/A - higher rate')
        : result.breakEvenMonths > 9999
            ? (isEs ? 'N/A - nunca' : 'N/A - never')
            : '${result.breakEvenMonths} $tMonths'
                ' (${(result.breakEvenMonths / 12).toStringAsFixed(1)} $tYears)';

    final verdictColor =
        result.refinanceMakesSense ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700;
    final verdictText = result.refinanceMakesSense
        ? (isEs
            ? 'Refinanciar tiene sentido - break-even en ${result.breakEvenMonths} $tMonths'
            : 'Refinancing makes sense - break-even in ${result.breakEvenMonths} $tMonths')
        : result.monthlySavings <= 0
            ? (isEs
                ? 'La nueva tasa es mayor - el refinanciamiento cuesta mas'
                : 'New rate is higher - refinancing costs more')
            : (isEs
                ? 'El periodo de recuperacion es largo - evalua bien antes de refinanciar'
                : 'Long break-even period - evaluate carefully before refinancing');

    final savingsColor = result.monthlySavings > 0
        ? PdfColor(0.13, 0.55, 0.33)
        : PdfColors.red700;
    final lifetimeSavingsColor = result.totalSavingsOverLife > 0
        ? PdfColor(0.13, 0.55, 0.33)
        : PdfColors.red700;
    final verdictBg = result.refinanceMakesSense
        ? PdfColor(0.90, 0.97, 0.92)
        : PdfColor(0.99, 0.93, 0.93);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────────────
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
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        // ── Two-column: current loan | new loan ────────────────────────────
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _sectionBox(tCurrent, [
                _row2(tBalance, _usd0.format(balance)),
                _row2(tCurRate, '${curRate.toStringAsFixed(2)}%'),
                _row2(tCurTerm, '$curYears $tYears'),
                _row2(tCurPayment, _usd2.format(result.oldMonthlyPayment)),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _sectionBox(tNew, [
                _row2(tNewRate, '${newRate.toStringAsFixed(2)}%'),
                _row2(tNewTerm, '$newYears $tYears'),
                _row2(tClosing, _usd2.format(closing)),
                _row2(tNewPayment, _usd2.format(result.newMonthlyPayment)),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        // ── Results ────────────────────────────────────────────────────────
        _sectionBox(tResults, [
          _row2(tMonthlySavings, _usd2.format(result.monthlySavings),
              bold: true, color: savingsColor),
          _row2(tBreakEven, breakEvenText),
          _row2(tTotalSavings, _usd0.format(result.totalSavingsOverLife),
              bold: true, color: lifetimeSavingsColor),
        ]),
        pw.SizedBox(height: 14),
        // ── Recommendation box ─────────────────────────────────────────────
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: verdictBg,
            border: pw.Border.all(color: verdictColor, width: 1.5),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(tRecommendation,
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9,
                        color: verdictColor)),
                pw.SizedBox(height: 4),
                pw.Text(verdictText,
                    style: pw.TextStyle(
                        fontSize: AppTextSize.xs, color: verdictColor)),
              ]),
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Investment Return PDF export ──────────────────────────────────────────

  static Future<void> exportInvestmentReturn(
    BuildContext context, {
    required double price,
    required double downPct,
    required double rent,
    required double appreciation,
    required int holdYears,
    required double rate,
    required double downAmt,
    required double initialInv,
    required double loanAmt,
    required double mortgageMo,
    required double monthlyCF,
    required double cashOnCash,
    required double irr,
    required double npv,
    required double equityMult,
    required bool isEs,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildInvestmentReturnPdf(_InvestmentReturnPdfParams(
        price: price, downPct: downPct, rent: rent,
        appreciation: appreciation, holdYears: holdYears, rate: rate,
        downAmt: downAmt, initialInv: initialInv, loanAmt: loanAmt,
        mortgageMo: mortgageMo, monthlyCF: monthlyCF, cashOnCash: cashOnCash,
        irr: irr, npv: npv, equityMult: equityMult, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_InvestmentReturn_${price.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildInvestmentReturnPage({
    required double price,
    required double downPct,
    required double rent,
    required double appreciation,
    required int holdYears,
    required double rate,
    required double downAmt,
    required double initialInv,
    required double loanAmt,
    required double mortgageMo,
    required double monthlyCF,
    required double cashOnCash,
    required double irr,
    required double npv,
    required double equityMult,
    required bool isEs,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Retorno de Inversión Inmobiliaria' : 'Real Estate Investment Return';
    final tInputs = isEs ? 'PARÁMETROS DE INVERSIÓN' : 'INVESTMENT PARAMETERS';
    final tPurchasePrice = isEs ? 'Precio de compra' : 'Purchase Price';
    final tDownPayment = isEs ? 'Enganche' : 'Down Payment';
    final tMonthlyRent = isEs ? 'Renta mensual' : 'Monthly Rent';
    final tAppreciation = isEs ? 'Apreciación anual' : 'Annual Appreciation';
    final tHoldPeriod = isEs ? 'Período de tenencia' : 'Hold Period';
    final tMortgageRate = isEs ? 'Tasa hipotecaria' : 'Mortgage Rate';
    final tYears = isEs ? 'años' : 'yrs';
    final tCashFlow = isEs ? 'FLUJO DE CAJA' : 'CASH FLOW';
    final tInitialInv = isEs ? 'Inversión inicial (enganche + cierre)' : 'Initial Investment (down + closing)';
    final tLoanAmt = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tMortgageMo = isEs ? 'Hipoteca mensual' : 'Monthly Mortgage';
    final tExpenses = isEs ? 'Gastos operativos (30%)' : 'Operating Expenses (30%)';
    final tMonthlyCF = isEs ? 'Flujo de caja mensual' : 'Monthly Cash Flow';
    final tAnnualCF = isEs ? 'Flujo de caja anual' : 'Annual Cash Flow';
    final tReturns = isEs ? 'RETORNOS' : 'RETURNS';
    final tCashOnCash = isEs ? 'ROI efectivo (cash-on-cash)' : 'Cash-on-Cash ROI';
    final tIrr = isEs ? 'TIR (tasa interna de retorno)' : 'IRR (Internal Rate of Return)';
    final tNpv = isEs ? 'VPN (valor presente neto)' : 'NPV (Net Present Value)';
    final tEquityMult = isEs ? 'Múltiplo de capital' : 'Equity Multiple';

    final expensesMo = rent * 0.30;
    final annualCF = monthlyCF * 12;

    // IRR verdict
    final verdictLabel = irr > 15
        ? (isEs ? 'Excelente — Gran inversión' : 'Excellent — Strong investment')
        : irr > 10
            ? (isEs ? 'Bueno — Inversión sólida' : 'Good — Solid investment')
            : irr > 6
                ? (isEs ? 'Regular — Retorno moderado' : 'Fair — Moderate return')
                : (isEs ? 'Bajo — Considerar alternativas' : 'Poor — Consider alternatives');
    final verdictColor = irr > 15
        ? PdfColor(0.13, 0.55, 0.33)
        : irr > 10
            ? PdfColor(0.13, 0.49, 0.77)
            : irr > 6
                ? PdfColor(0.80, 0.55, 0.0)
                : PdfColors.red700;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(height: 2, color: _navy, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        // Verdict banner
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor(verdictColor.red, verdictColor.green, verdictColor.blue, 0.10),
            border: pw.Border.all(color: verdictColor, width: 1.0),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(verdictLabel, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: verdictColor)),
              pw.Text('${irr.toStringAsFixed(1)}${isEs ? '% TIR' : '% IRR'}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: verdictColor)),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tInputs, [
                  _row2(tPurchasePrice, _usd0.format(price)),
                  _row2(tDownPayment, '${_usd0.format(downAmt)} (${downPct.toStringAsFixed(1)}%)'),
                  _row2(tMonthlyRent, _usd0.format(rent)),
                  _row2(tAppreciation, '${appreciation.toStringAsFixed(1)}%'),
                  _row2(tHoldPeriod, '$holdYears $tYears'),
                  _row2(tMortgageRate, '${rate.toStringAsFixed(2)}%'),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tCashFlow, [
                  _row2(tInitialInv, _usd0.format(initialInv)),
                  _row2(tLoanAmt, _usd0.format(loanAmt)),
                  _row2(tMortgageMo, _usd2.format(mortgageMo)),
                  _row2(tExpenses, _usd2.format(expensesMo)),
                  _row2(tMonthlyCF, '${monthlyCF >= 0 ? '+' : ''}${_usd2.format(monthlyCF)}',
                      bold: true, color: monthlyCF >= 0 ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700),
                  _row2(tAnnualCF, '${annualCF >= 0 ? '+' : ''}${_usd0.format(annualCF)}',
                      bold: true, color: annualCF >= 0 ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tReturns, [
                  _row2(tCashOnCash, '${cashOnCash.toStringAsFixed(1)}%',
                      bold: true, color: cashOnCash >= 6 ? PdfColor(0.13, 0.55, 0.33) : PdfColor(0.80, 0.55, 0.0)),
                  _row2(tIrr, '${irr.toStringAsFixed(1)}%', bold: true, color: verdictColor),
                  _row2(tNpv, '${npv >= 0 ? '+' : ''}${_usd0.format(npv)}',
                      bold: true, color: npv >= 0 ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700),
                  _row2(tEquityMult, '${equityMult.toStringAsFixed(2)}x'),
                ]),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── PMI Calculator PDF export ─────────────────────────────────────────────

  static Future<void> exportPmiCalculator(
    BuildContext context, {
    required double homePrice,
    required double downPct,
    required double loanAmount,
    required double ltv,
    required int creditScore,
    required double pmiAnnualRate,
    required double monthlyPmi,
    required int? monthsTo80,
    required int? monthsTo78,
    required double rate,
    required bool isEs,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildPmiCalculatorPdf(_PmiCalculatorPdfParams(
        homePrice: homePrice, downPct: downPct, loanAmount: loanAmount,
        ltv: ltv, creditScore: creditScore, pmiAnnualRate: pmiAnnualRate,
        monthlyPmi: monthlyPmi, monthsTo80: monthsTo80, monthsTo78: monthsTo78,
        rate: rate, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_PMI_${homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildPmiCalculatorPage({
    required double homePrice,
    required double downPct,
    required double loanAmount,
    required double ltv,
    required int creditScore,
    required double pmiAnnualRate,
    required double monthlyPmi,
    required int? monthsTo80,
    required int? monthsTo78,
    required double rate,
    required bool isEs,
  }) {
    final now = DateTime.now();
    final downAmt = homePrice * downPct / 100.0;
    final annualPmi = monthlyPmi * 12;
    final totalPmiTo78 = monthsTo78 != null ? monthlyPmi * monthsTo78 : 0.0;

    final tReport = isEs ? 'Calculadora de PMI' : 'PMI Calculator';
    final tLoanInfo = isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tHomePrice = isEs ? 'Precio de la vivienda' : 'Home Price';
    final tDownPayment = isEs ? 'Pago inicial' : 'Down Payment';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tLtv = 'LTV Ratio';
    final tCreditScore = isEs ? 'Puntaje crediticio' : 'Credit Score';
    final tRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tPmiSection = isEs ? 'ANÁLISIS PMI' : 'PMI ANALYSIS';
    final tPmiAnnualRate = isEs ? 'Tasa PMI anual' : 'PMI Annual Rate';
    final tMonthlyPmi = isEs ? 'PMI mensual' : 'Monthly PMI';
    final tAnnualPmi = isEs ? 'PMI anual' : 'Annual PMI';
    final tCancelAt80 = isEs ? 'Cancelación voluntaria (LTV 80%)' : 'Cancel-on-request (LTV 80%)';
    final tAutoCancel78 = isEs ? 'Cancelación automática (LTV 78%)' : 'Auto-cancel (LTV 78%)';
    final tTotalPmi = isEs ? 'PMI total hasta cancelación auto.' : 'Total PMI until auto-cancel';
    final tNote = isEs ? 'Nota' : 'Note';
    final tNoteText = isEs
        ? 'PMI puede cancelarse a solicitud al alcanzar 80% LTV; cancelación obligatoria a 78% LTV.'
        : 'PMI may be cancelled on request at 80% LTV; mandatory cancellation at 78% LTV.';

    String fmtMonths(int? m) {
      if (m == null) return isEs ? 'N/A' : 'N/A';
      if (m == 0) return isEs ? 'Ya alcanzado' : 'Already reached';
      return '${m ~/ 12}${isEs ? ' años' : ' yrs'} ${m % 12}${isEs ? ' meses' : ' mo'}';
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(height: 2, color: _navy, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _sectionBox(tLoanInfo, [
                _row2(tHomePrice, _usd0.format(homePrice)),
                _row2(tDownPayment, '${_usd0.format(downAmt)} (${downPct.toStringAsFixed(1)}%)'),
                _row2(tLoanAmount, _usd0.format(loanAmount)),
                _row2(tLtv, '${ltv.toStringAsFixed(1)}%',
                    color: ltv > 95 ? PdfColors.red700 : ltv > 90 ? PdfColor(0.80, 0.45, 0.0) : _navy),
                _row2(tCreditScore, creditScore.toString()),
                _row2(tRate, '${rate.toStringAsFixed(2)}%'),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _sectionBox(tPmiSection, [
                _row2(tPmiAnnualRate, '${pmiAnnualRate.toStringAsFixed(2)}%'),
                _row2(tMonthlyPmi, _usd2.format(monthlyPmi), bold: true, color: _gold),
                _row2(tAnnualPmi, _usd0.format(annualPmi)),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Divider(color: PdfColors.grey300, height: 6)),
                _row2(tCancelAt80, fmtMonths(monthsTo80)),
                _row2(tAutoCancel78, fmtMonths(monthsTo78), bold: true),
                if (monthsTo78 != null)
                  _row2(tTotalPmi, _usd0.format(totalPmiTo78)),
                _row2(tNote, tNoteText, small: true),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Points / Discount PDF export ──────────────────────────────────────────

  static Future<void> exportPoints(
    BuildContext context, {
    required double loanAmount,
    required double origRate,
    required double points,
    required int termYears,
    required double newRate,
    required double pointsCost,
    required double origPayment,
    required double newPayment,
    required double monthlySavings,
    required double? breakevenMonths,
    required double lifetimeSavings,
    required bool isEs,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildPointsPdf(_PointsPdfParams(
        loanAmount: loanAmount, origRate: origRate, points: points,
        termYears: termYears, newRate: newRate, pointsCost: pointsCost,
        origPayment: origPayment, newPayment: newPayment,
        monthlySavings: monthlySavings, breakevenMonths: breakevenMonths,
        lifetimeSavings: lifetimeSavings, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_Points_${loanAmount.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildPointsPage({
    required double loanAmount,
    required double origRate,
    required double points,
    required int termYears,
    required double newRate,
    required double pointsCost,
    required double origPayment,
    required double newPayment,
    required double monthlySavings,
    required double? breakevenMonths,
    required double lifetimeSavings,
    required bool isEs,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Análisis de Puntos de Descuento' : 'Discount Points Analysis';
    final tLoanInfo = isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tOrigRate = isEs ? 'Tasa original' : 'Original Rate';
    final tPoints = isEs ? 'Puntos comprados' : 'Points Purchased';
    final tTerm = isEs ? 'Plazo' : 'Term';
    final tYears = isEs ? 'años' : 'years';
    final tResults = isEs ? 'RESULTADOS' : 'RESULTS';
    final tPointsCost = isEs ? 'Costo de los puntos' : 'Points Cost';
    final tNewRate = isEs ? 'Tasa nueva' : 'New Rate';
    final tOrigPayment = isEs ? 'Pago mensual original' : 'Original Monthly Payment';
    final tNewPayment = isEs ? 'Pago mensual nuevo' : 'New Monthly Payment';
    final tMonthlySav = isEs ? 'Ahorro mensual' : 'Monthly Savings';
    final tBreakeven = isEs ? 'Punto de equilibrio' : 'Breakeven';
    final tLifetimeSav = isEs ? 'Ahorro neto ($termYears ${isEs ? 'años' : 'yrs'})' : 'Net Savings ($termYears yrs)';
    final tRecommendation = isEs ? 'RECOMENDACIÓN' : 'RECOMMENDATION';

    String breakevenStr() {
      if (breakevenMonths == null) return isEs ? 'N/A (no hay ahorro)' : 'N/A (no savings)';
      final m = breakevenMonths.ceil();
      return '${m ~/ 12}${isEs ? ' años' : ' yrs'} ${m % 12}${isEs ? ' meses' : ' mo'}';
    }

    final worthIt = breakevenMonths != null && breakevenMonths < termYears * 12;
    final verdictColor = worthIt ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700;
    final verdictBg = worthIt ? PdfColor(0.90, 0.97, 0.92) : PdfColor(0.99, 0.93, 0.93);
    final verdictText = breakevenMonths == null
        ? (isEs ? 'No hay ahorro con estos puntos — no vale la pena.' : 'No savings with these points — not worth it.')
        : worthIt
            ? (isEs
                ? 'Vale la pena — punto de equilibrio antes del plazo completo.'
                : 'Worth it — breakeven before the full loan term.')
            : (isEs
                ? 'No vale la pena — el punto de equilibrio supera el plazo del préstamo.'
                : 'Not worth it — breakeven exceeds the loan term.');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(height: 2, color: _navy, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _sectionBox(tLoanInfo, [
                _row2(tLoanAmount, _usd0.format(loanAmount)),
                _row2(tOrigRate, '${origRate.toStringAsFixed(2)}%'),
                _row2(tPoints, points.toStringAsFixed(2)),
                _row2(tTerm, '$termYears $tYears'),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _sectionBox(tResults, [
                _row2(tPointsCost, _usd0.format(pointsCost), color: _gold),
                _row2(tNewRate, '${newRate.toStringAsFixed(3)}%'),
                _row2(tOrigPayment, _usd2.format(origPayment)),
                _row2(tNewPayment, _usd2.format(newPayment)),
                _row2(tMonthlySav, _usd2.format(monthlySavings), bold: true,
                    color: PdfColor(0.13, 0.55, 0.33)),
                _row2(tBreakeven, breakevenStr(), bold: true),
                _row2(tLifetimeSav, _usd0.format(lifetimeSavings), bold: true,
                    color: lifetimeSavings >= 0 ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: verdictBg,
            border: pw.Border.all(color: verdictColor, width: 1.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(tRecommendation,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: verdictColor)),
            pw.SizedBox(height: 4),
            pw.Text(verdictText,
                style: pw.TextStyle(fontSize: AppTextSize.xs, color: verdictColor)),
          ]),
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── USDA Loan PDF export ──────────────────────────────────────────────────

  static Future<void> exportUsda(
    BuildContext context, {
    required double homePrice,
    required double income,
    required double rate,
    required int termYears,
    required bool ruralEligible,
    required bool incomeOk,
    required double maxIncome,
    required double upfrontFee,
    required double loanAmount,
    required double monthlyAnnualFee,
    required double pAndI,
    required double propertyTax,
    required double insurance,
    required double totalMonthly,
    required bool isEs,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildUsdaPdf(_UsdaPdfParams(
        homePrice: homePrice, income: income, rate: rate,
        termYears: termYears, ruralEligible: ruralEligible, incomeOk: incomeOk,
        maxIncome: maxIncome, upfrontFee: upfrontFee, loanAmount: loanAmount,
        monthlyAnnualFee: monthlyAnnualFee, pAndI: pAndI,
        propertyTax: propertyTax, insurance: insurance,
        totalMonthly: totalMonthly, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_USDA_${homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildUsdaPage({
    required double homePrice,
    required double income,
    required double rate,
    required int termYears,
    required bool ruralEligible,
    required bool incomeOk,
    required double maxIncome,
    required double upfrontFee,
    required double loanAmount,
    required double monthlyAnnualFee,
    required double pAndI,
    required double propertyTax,
    required double insurance,
    required double totalMonthly,
    required bool isEs,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Calculadora de Préstamo USDA' : 'USDA Loan Calculator';
    final tEligibility = isEs ? 'ELEGIBILIDAD' : 'ELIGIBILITY';
    final tHomePrice = isEs ? 'Precio de la vivienda' : 'Home Price';
    final tIncome = isEs ? 'Ingreso anual del hogar' : 'Annual Household Income';
    final tIncomeLimit = isEs ? 'Límite de ingreso (115% AMI)' : 'Income Limit (115% AMI)';
    final tRuralArea = isEs ? 'Zona rural elegible' : 'Rural area eligible';
    final tIncomeStatus = isEs ? 'Estado del ingreso' : 'Income status';
    final tLoanDetails = isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tDownPayment = isEs ? 'Pago inicial' : 'Down Payment';
    final tUpfrontFee = isEs ? 'Tarifa garantía inicial (1%)' : 'Upfront Guarantee Fee (1%)';
    final tLoanAmount = isEs ? 'Monto del préstamo (financiado)' : 'Loan Amount (financed)';
    final tRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tTerm = isEs ? 'Plazo' : 'Term';
    final tYears = isEs ? 'años' : 'years';
    final tPayment = isEs ? 'PAGO MENSUAL' : 'MONTHLY PAYMENT';
    final tAnnualFee = isEs ? 'Tarifa anual mensualizada (0.35%)' : 'Monthly Annual Fee (0.35%)';
    final tPandI = isEs ? 'Capital + Interés' : 'P & I';
    final tTax = isEs ? 'Impuesto predial' : 'Property Tax';
    final tIns = isEs ? 'Seguro' : 'Insurance';
    final tTotal = isEs ? 'Pago total mensual' : 'Total Monthly Payment';

    final eligible = ruralEligible && incomeOk;
    final eligColor = eligible ? PdfColor(0.13, 0.55, 0.33) : PdfColor(0.80, 0.55, 0.0);
    final eligBg = eligible ? PdfColor(0.90, 0.97, 0.92) : PdfColor(1.0, 0.96, 0.88);
    final eligText = eligible
        ? (isEs ? 'Elegible para préstamo USDA' : 'Eligible for USDA loan')
        : !ruralEligible
            ? (isEs ? 'Zona no elegible para USDA' : 'Area not eligible for USDA')
            : (isEs ? 'Ingreso supera el límite USDA' : 'Income exceeds USDA limit');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(height: 2, color: _navy, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        // Eligibility banner
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: eligBg,
            border: pw.Border.all(color: eligColor, width: 1.0),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Text(eligText,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: eligColor)),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tEligibility, [
                  _row2(tHomePrice, _usd0.format(homePrice)),
                  _row2(tIncome, _usd0.format(income)),
                  _row2(tIncomeLimit, _usd0.format(maxIncome)),
                  _row2(tRuralArea, ruralEligible ? (isEs ? 'Sí' : 'Yes') : (isEs ? 'No' : 'No')),
                  _row2(tIncomeStatus,
                      incomeOk ? (isEs ? 'Dentro del límite' : 'Within limit') : (isEs ? 'Supera el límite' : 'Exceeds limit'),
                      color: incomeOk ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tLoanDetails, [
                  _row2(tDownPayment, isEs ? '0% (sin enganche)' : '0% (no down payment)'),
                  _row2(tUpfrontFee, _usd0.format(upfrontFee)),
                  _row2(tLoanAmount, _usd0.format(loanAmount)),
                  _row2(tRate, '${rate.toStringAsFixed(2)}%'),
                  _row2(tTerm, '$termYears $tYears'),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tPayment, [
                  _row2(tPandI, _usd2.format(pAndI)),
                  _row2(tAnnualFee, _usd2.format(monthlyAnnualFee)),
                  _row2(tTax, _usd2.format(propertyTax)),
                  _row2(tIns, _usd2.format(insurance)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Divider(color: PdfColors.grey300, height: 6)),
                  _row2(tTotal, _usd2.format(totalMonthly), bold: true, color: _navy),
                ]),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── VA Loan PDF export ────────────────────────────────────────────────────

  static Future<void> exportVa(
    BuildContext context, {
    required double homePrice,
    required double downPct,
    required double downAmt,
    required double ffRate,
    required double fundingFee,
    required double loanAmount,
    required double rate,
    required int termYears,
    required bool reserves,
    required bool subsequent,
    required double pAndI,
    required double propertyTax,
    required double insurance,
    required double totalMonthly,
    required bool isEs,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildVaPdf(_VaPdfParams(
        homePrice: homePrice, downPct: downPct, downAmt: downAmt,
        ffRate: ffRate, fundingFee: fundingFee, loanAmount: loanAmount,
        rate: rate, termYears: termYears, reserves: reserves,
        subsequent: subsequent, pAndI: pAndI, propertyTax: propertyTax,
        insurance: insurance, totalMonthly: totalMonthly, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_VA_${homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildVaPage({
    required double homePrice,
    required double downPct,
    required double downAmt,
    required double ffRate,
    required double fundingFee,
    required double loanAmount,
    required double rate,
    required int termYears,
    required bool reserves,
    required bool subsequent,
    required double pAndI,
    required double propertyTax,
    required double insurance,
    required double totalMonthly,
    required bool isEs,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Calculadora de Préstamo VA' : 'VA Loan Calculator';
    final tLoanInfo = isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tHomePrice = isEs ? 'Precio de la vivienda' : 'Home Price';
    final tDownPayment = isEs ? 'Pago inicial' : 'Down Payment';
    final tServiceType = isEs ? 'Tipo de servicio' : 'Service Type';
    final tFfRate = isEs ? 'Tasa tarifa de financiación' : 'Funding Fee Rate';
    final tFundingFee = isEs ? 'Tarifa de financiación' : 'Funding Fee';
    final tLoanAmount = isEs ? 'Monto del préstamo (incl. tarifa)' : 'Loan Amount (incl. fee)';
    final tRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tTerm = isEs ? 'Plazo' : 'Term';
    final tYears = isEs ? 'años' : 'years';
    final tPayment = isEs ? 'PAGO MENSUAL' : 'MONTHLY PAYMENT';
    final tPandI = isEs ? 'Capital + Interés' : 'P & I';
    final tNoPmi = isEs ? 'PMI' : 'PMI';
    final tTax = isEs ? 'Impuesto predial' : 'Property Tax';
    final tIns = isEs ? 'Seguro' : 'Insurance';
    final tTotal = isEs ? 'Pago total mensual' : 'Total Monthly Payment';

    final serviceLabel = subsequent
        ? (isEs ? 'Uso subsiguiente' : 'Subsequent use')
        : reserves
            ? (isEs ? 'Reservas / Guardia Nacional' : 'Reserves / National Guard')
            : (isEs ? 'Regular (primer uso)' : 'Regular (first use)');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(height: 2, color: _navy, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        // No PMI badge
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor(0.90, 0.97, 0.92),
            border: pw.Border.all(color: PdfColor(0.13, 0.55, 0.33), width: 1.0),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Text(
            isEs ? 'Sin PMI — Beneficio exclusivo VA' : 'No PMI Required — VA Benefit',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor(0.13, 0.55, 0.33)),
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _sectionBox(tLoanInfo, [
                _row2(tHomePrice, _usd0.format(homePrice)),
                _row2(tDownPayment, '${_usd0.format(downAmt)} (${downPct.toStringAsFixed(1)}%)'),
                _row2(tServiceType, serviceLabel),
                _row2(tFfRate, '${(ffRate * 100).toStringAsFixed(2)}%'),
                _row2(tFundingFee, _usd0.format(fundingFee), color: _gold),
                _row2(tLoanAmount, _usd0.format(loanAmount)),
                _row2(tRate, '${rate.toStringAsFixed(2)}%'),
                _row2(tTerm, '$termYears $tYears'),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tPayment, [
                  _row2(tPandI, _usd2.format(pAndI)),
                  _row2(tNoPmi, isEs ? 'No aplica (beneficio VA)' : 'N/A (VA benefit)'),
                  _row2(tTax, _usd2.format(propertyTax)),
                  _row2(tIns, _usd2.format(insurance)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Divider(color: PdfColors.grey300, height: 6)),
                  _row2(tTotal, _usd2.format(totalMonthly), bold: true, color: _navy),
                ]),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Affordability PDF export ──────────────────────────────────────────────

  static Future<void> exportAffordability(
    BuildContext context, {
    required double annualIncome,
    required double monthlyDebts,
    required double downPayment,
    required double annualRatePct,
    required int termYears,
    required double propertyTaxRatePct,
    required double homeInsuranceAnnual,
    required double hoaMonthly,
    required AffordabilityResult result,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildAffordabilityPdf(_AffordabilityPdfParams(
        annualIncome: annualIncome, monthlyDebts: monthlyDebts,
        downPayment: downPayment, annualRatePct: annualRatePct,
        termYears: termYears,
        propertyTaxRatePct: propertyTaxRatePct,
        homeInsuranceAnnual: homeInsuranceAnnual,
        hoaMonthly: hoaMonthly,
        result: result, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_Affordability_${annualIncome.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildAffordabilityPage({
    required double annualIncome,
    required double monthlyDebts,
    required double downPayment,
    required double annualRatePct,
    required int termYears,
    required double propertyTaxRatePct,
    required double homeInsuranceAnnual,
    required double hoaMonthly,
    required AffordabilityResult result,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Análisis de Asequibilidad' : 'Affordability Analysis';
    final tInputs = isEs ? 'DATOS DE ENTRADA' : 'INPUTS';
    final tAnnualIncome = isEs ? 'Ingreso bruto anual' : 'Annual Gross Income';
    final tMonthlyDebts = isEs ? 'Deudas mensuales' : 'Monthly Debts';
    final tDownPayment = isEs ? 'Pago inicial disponible' : 'Down Payment';
    final tRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tTerm = isEs ? 'Plazo' : 'Loan Term';
    final tYears = isEs ? 'años' : 'years';
    final tTaxRateInput = isEs ? 'Tasa impuesto predial' : 'Property Tax Rate';
    final tInsuranceInput = isEs ? 'Seguro del hogar (anual)' : 'Home Insurance (annual)';
    final tHoaInput = isEs ? 'HOA mensual' : 'HOA Monthly';
    final tResults = isEs ? 'PRECIOS MÁXIMOS' : 'MAX HOME PRICES';
    final tConservative = isEs ? 'Conservador (28% DTI)' : 'Conservative (28% DTI)';
    final tStandard = isEs ? 'Estándar (43% DTI)' : 'Standard (43% DTI)';
    final tMaxLoanConservative = isEs ? 'Préstamo máx. conservador' : 'Max Loan – Conservative';
    final tMaxLoanStandard = isEs ? 'Préstamo máx. estándar' : 'Max Loan – Standard';
    final tMonthly = isEs ? 'DESGLOSE MENSUAL' : 'MONTHLY BREAKDOWN';
    final tPI = isEs ? 'Capital e Interés' : 'P & I';
    final tTax = isEs ? 'Impuesto predial' : 'Property Tax';
    final tIns = isEs ? 'Seguro del hogar' : 'Home Insurance';
    final tPMI = 'PMI';
    final tHOA = 'HOA';
    final tTotalMonthly = isEs ? 'Total mensual estimado' : 'Est. Total Monthly';
    final tVerdictSection = isEs ? 'DIAGNÓSTICO DTI' : 'DTI VERDICT';
    final monthlyIncome = result.monthlyGrossIncome;
    final backEndDti =
        monthlyIncome > 0 ? (result.totalMonthly / monthlyIncome) * 100 : 0.0;
    final verdictColor = backEndDti <= 28
        ? PdfColor(0.13, 0.55, 0.33)
        : backEndDti <= 36
            ? PdfColor(0.80, 0.55, 0.00)
            : PdfColors.red700;
    final verdictText = backEndDti <= 28
        ? (isEs ? 'Excelente — DTI ≤ 28%' : 'Excellent — DTI ≤ 28%')
        : backEndDti <= 36
            ? (isEs ? 'Aceptable — DTI 29–36%' : 'Acceptable — DTI 29–36%')
            : (isEs ? 'Alto — DTI > 36%' : 'High — DTI > 36%');
    final verdictBg = backEndDti <= 28
        ? PdfColor(0.90, 0.97, 0.92)
        : backEndDti <= 36
            ? PdfColor(0.99, 0.97, 0.88)
            : PdfColor(0.99, 0.93, 0.93);
    final maxHomePrice = result.maxHomePriceStandard > 0
        ? result.maxHomePriceStandard
        : result.maxHomePriceConservative;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppTextSize.xs,
                          color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tInputs, [
                  _row2(tAnnualIncome, _usd0.format(annualIncome)),
                  _row2(tMonthlyDebts, _usd0.format(monthlyDebts)),
                  _row2(tDownPayment, _usd0.format(downPayment)),
                  _row2(tRate, '${annualRatePct.toStringAsFixed(2)}%'),
                  _row2(tTerm, '$termYears $tYears'),
                  _row2(tTaxRateInput, '${propertyTaxRatePct.toStringAsFixed(2)}%'),
                  _row2(tInsuranceInput, _usd0.format(homeInsuranceAnnual)),
                  if (hoaMonthly > 0)
                    _row2(tHoaInput, _usd0.format(hoaMonthly)),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tVerdictSection, [
                  _row2(
                    isEs
                        ? 'DTI estimado (back-end)'
                        : 'Est. Back-End DTI',
                    '${backEndDti.toStringAsFixed(1)}%',
                    bold: true,
                    color: verdictColor,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: verdictBg,
                      border:
                          pw.Border.all(color: verdictColor, width: 1),
                      borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4)),
                    ),
                    child: pw.Text(verdictText,
                        style: pw.TextStyle(
                            fontSize: AppTextSize.xs,
                            fontWeight: pw.FontWeight.bold,
                            color: verdictColor)),
                  ),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tResults, [
                  _row2(tConservative,
                      _usd0.format(result.maxHomePriceConservative),
                      bold: true,
                      color: PdfColor(0.13, 0.55, 0.33)),
                  _row2(tStandard, _usd0.format(maxHomePrice),
                      bold: true, color: _navy),
                  _row2(tMaxLoanConservative,
                      _usd0.format(result.maxLoanConservative)),
                  _row2(tMaxLoanStandard,
                      _usd0.format(result.maxLoanStandard)),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tMonthly, [
                  _row2(tPI, _usd2.format(result.monthlyPI)),
                  _row2(tTax, _usd2.format(result.monthlyTax)),
                  _row2(tIns, _usd2.format(result.monthlyInsurance)),
                  if (result.monthlyPMI > 0)
                    _row2(tPMI, _usd2.format(result.monthlyPMI),
                        color: PdfColors.orange700),
                  if (result.monthlyHOA > 0)
                    _row2(tHOA, _usd2.format(result.monthlyHOA)),
                  pw.Divider(color: PdfColors.grey300, height: 6),
                  _row2(tTotalMonthly, _usd2.format(result.totalMonthly),
                      bold: true, color: _navy),
                ]),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── ARM PDF export ────────────────────────────────────────────────────────

  static Future<void> exportArm(
    BuildContext context, {
    required double loanAmount,
    required double initialRatePct,
    required int fixedYears,
    required double adjustedRatePct,
    required int termYears,
    required ARMResult result,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildArmPdf(_ArmPdfParams(
        loanAmount: loanAmount, initialRatePct: initialRatePct,
        fixedYears: fixedYears, adjustedRatePct: adjustedRatePct,
        termYears: termYears, result: result, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_ARM_${loanAmount.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildArmPage({
    required double loanAmount,
    required double initialRatePct,
    required int fixedYears,
    required double adjustedRatePct,
    required int termYears,
    required ARMResult result,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final tReport =
        isEs ? 'Hipoteca de Tasa Ajustable (ARM)' : 'Adjustable Rate Mortgage (ARM)';
    final tLoanInfo = isEs ? 'DATOS DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tInitialRate = isEs ? 'Tasa inicial' : 'Initial Rate';
    final tFixedPeriod = isEs ? 'Período fijo' : 'Fixed Period';
    final tAdjRate = isEs ? 'Tasa ajustada' : 'Adjusted Rate';
    final tTotalTerm = isEs ? 'Plazo total' : 'Total Term';
    final tYears = isEs ? 'años' : 'years';
    final tPayments = isEs ? 'PAGOS CALCULADOS' : 'PAYMENT SCHEDULE';
    final tInitialPayment =
        isEs ? 'Pago durante período fijo' : 'Payment – Fixed Period';
    final tAdjPayment = isEs ? 'Pago después del reset' : 'Payment after Reset';
    final tBalanceAtReset = isEs ? 'Saldo al reset' : 'Balance at Reset';
    final tComparison =
        isEs ? 'COMPARACIÓN vs. TASA FIJA' : 'COMPARISON vs. FIXED RATE';
    final tArmTotalInterest =
        isEs ? 'Interés total (ARM)' : 'Total Interest (ARM)';
    final tFixedTotalInterest =
        isEs ? 'Interés total (tasa fija equiv.)' : 'Total Interest (Fixed equiv.)';
    final tDifference = isEs ? 'Diferencia' : 'Difference';
    final tBreakEven = isEs ? 'Punto de cruce' : 'Break-Even Point';
    final interestDiff = result.totalInterest - result.fixedTotalInterest;
    final armCheaper = interestDiff < 0;
    final diffColor = armCheaper ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700;
    final breakEvenText = result.breakEvenMonths == null
        ? (isEs ? 'ARM siempre más barata' : 'ARM always cheaper')
        : '${result.breakEvenMonths} mo (${(result.breakEvenMonths! / 12).toStringAsFixed(1)} $tYears)';
    final paymentJumpColor =
        result.payment2 > result.payment1 ? PdfColors.red700 : PdfColor(0.13, 0.55, 0.33);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppTextSize.xs,
                          color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tLoanInfo, [
                  _row2(tLoanAmount, _usd0.format(loanAmount)),
                  _row2(tInitialRate, '${initialRatePct.toStringAsFixed(2)}%'),
                  _row2(tFixedPeriod, '$fixedYears $tYears'),
                  _row2(tAdjRate, '${adjustedRatePct.toStringAsFixed(2)}%'),
                  _row2(tTotalTerm, '$termYears $tYears'),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tPayments, [
                  _row2(tInitialPayment, _usd2.format(result.payment1),
                      bold: true, color: _navy),
                  _row2(tAdjPayment, _usd2.format(result.payment2),
                      bold: true, color: paymentJumpColor),
                  _row2(tBalanceAtReset, _usd0.format(result.balanceAtReset)),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tComparison, [
                  _row2(tArmTotalInterest, _usd0.format(result.totalInterest)),
                  _row2(tFixedTotalInterest,
                      _usd0.format(result.fixedTotalInterest)),
                  _row2(
                    tDifference,
                    '${armCheaper ? "-" : "+"}${_usd0.format(interestDiff.abs())}',
                    bold: true,
                    color: diffColor,
                  ),
                  _row2(tBreakEven, breakEvenText),
                ]),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Closing Costs PDF export ───────────────────────────────────────────────

  static Future<void> exportClosingCosts(
    BuildContext context, {
    required double homePrice,
    required String state,
    required String loanType,
    required bool isBuyer,
    required List<Map<String, dynamic>> lineItems,
    required double total,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildClosingCostsPdf(_ClosingCostsPdfParams(
        homePrice: homePrice, state: state, loanType: loanType,
        isBuyer: isBuyer, lineItems: lineItems, total: total, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_ClosingCosts_${homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildClosingCostsPage({
    required double homePrice,
    required String state,
    required String loanType,
    required bool isBuyer,
    required List<Map<String, dynamic>> lineItems,
    required double total,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final tReport =
        isEs ? 'Costos de Cierre Estimados' : 'Estimated Closing Costs';
    final tInputs = isEs ? 'PARÁMETROS' : 'PARAMETERS';
    final tHomePrice = isEs ? 'Precio de compra' : 'Home Price';
    final tState = isEs ? 'Estado' : 'State';
    final tLoanType = isEs ? 'Tipo de préstamo' : 'Loan Type';
    final tPerspective = isEs ? 'Perspectiva' : 'Perspective';
    final tBuyer = isEs ? 'Comprador' : 'Buyer';
    final tSeller = isEs ? 'Vendedor' : 'Seller';
    final tBreakdown = isEs ? 'DESGLOSE DE COSTOS' : 'COST BREAKDOWN';
    final tTotalCosts = isEs ? 'RESUMEN' : 'SUMMARY';
    final pct = homePrice > 0 ? total / homePrice * 100.0 : 0.0;

    final tableData = lineItems
        .map((l) => [
              isEs ? l['labelEs'] as String : l['labelEn'] as String,
              _usd0.format(l['amount'] as double),
              '${total > 0 ? ((l['amount'] as double) / total * 100).toStringAsFixed(1) : '0'}%',
            ])
        .toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppTextSize.xs,
                          color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        _sectionBox(tInputs, [
          _row2(tHomePrice, _usd0.format(homePrice)),
          _row2(tState, state),
          _row2(tLoanType, loanType),
          _row2(tPerspective, isBuyer ? tBuyer : tSeller),
        ]),
        pw.SizedBox(height: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: _navy,
              child: pw.Text(tBreakdown,
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(AppSpacing.sm),
              decoration: pw.BoxDecoration(
                  border:
                      pw.Border.all(color: PdfColors.grey300, width: 0.5)),
              child: pw.TableHelper.fromTextArray(
                headers: [
                  isEs ? 'Concepto' : 'Item',
                  isEs ? 'Monto' : 'Amount',
                  '%',
                ],
                data: tableData,
                headerStyle: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: _navy),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellHeight: 16,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
                rowDecoration:
                    const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration: pw.BoxDecoration(color: _light),
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FixedColumnWidth(36),
                },
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        _sectionBox(tTotalCosts, [
          _row2(isEs ? 'Total estimado' : 'Estimated Total',
              _usd0.format(total),
              bold: true, color: _navy),
          _row2(isEs ? '% del precio de compra' : '% of Home Price',
              '${pct.toStringAsFixed(1)}%'),
        ]),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── DTI PDF export ────────────────────────────────────────────────────────

  static Future<void> exportDti(
    BuildContext context, {
    required double annualIncome,
    required double piti,
    required double carPayment,
    required double studentLoans,
    required double creditCards,
    required double otherDebts,
    required double frontEndDti,
    required double backEndDti,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildDtiPdf(_DtiPdfParams(
        annualIncome: annualIncome, piti: piti, carPayment: carPayment,
        studentLoans: studentLoans, creditCards: creditCards,
        otherDebts: otherDebts, frontEndDti: frontEndDti,
        backEndDti: backEndDti, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_DTI_${annualIncome.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildDtiPage({
    required double annualIncome,
    required double piti,
    required double carPayment,
    required double studentLoans,
    required double creditCards,
    required double otherDebts,
    required double frontEndDti,
    required double backEndDti,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final monthlyIncome = annualIncome / 12;
    final tReport =
        isEs ? 'Análisis DTI (Deuda vs. Ingreso)' : 'DTI (Debt-to-Income) Analysis';
    final tIncome = isEs ? 'INGRESOS' : 'INCOME';
    final tAnnualIncome = isEs ? 'Ingreso bruto anual' : 'Annual Gross Income';
    final tMonthlyIncome = isEs ? 'Ingreso mensual' : 'Monthly Income';
    final tDebts = isEs ? 'DEUDAS MENSUALES' : 'MONTHLY DEBTS';
    final tPITI = isEs ? 'Pago PITI (vivienda)' : 'PITI (Housing)';
    final tCar = isEs ? 'Auto' : 'Car Payment';
    final tStudent = isEs ? 'Préstamo estudiantil' : 'Student Loan';
    final tCards = isEs ? 'Tarjetas de crédito' : 'Credit Cards';
    final tOther = isEs ? 'Otras deudas' : 'Other Debts';
    final tDtiResults = isEs ? 'RATIOS DTI' : 'DTI RATIOS';
    final tFrontEnd =
        isEs ? 'DTI Front-End (solo vivienda)' : 'Front-End DTI (Housing only)';
    final tBackEnd =
        isEs ? 'DTI Back-End (total)' : 'Back-End DTI (Total)';
    final tEligibility =
        isEs ? 'ELEGIBILIDAD POR TIPO DE PRÉSTAMO' : 'ELIGIBILITY BY LOAN TYPE';

    PdfColor dtiColor(double dti, double good, double warn) {
      if (dti <= good) return PdfColor(0.13, 0.55, 0.33);
      if (dti <= warn) return PdfColor(0.80, 0.55, 0.00);
      return PdfColors.red700;
    }

    String dtiVerdict(double dti, double good, double warn) {
      if (dti <= good) return isEs ? 'Excelente' : 'Excellent';
      if (dti <= warn) return isEs ? 'Aceptable' : 'Acceptable';
      return isEs ? 'Alto' : 'High';
    }

    final frontColor = dtiColor(frontEndDti, 28, 36);
    final backColor = dtiColor(backEndDti, 36, 43);

    final eligData = [
      [
        'Conventional',
        'Front ≤ 28%, Back ≤ 36%',
        frontEndDti <= 28 && backEndDti <= 36
            ? (isEs ? 'Elegible' : 'Eligible')
            : (isEs ? 'No elegible' : 'Not eligible'),
      ],
      [
        'FHA',
        'Front ≤ 31%, Back ≤ 43%',
        frontEndDti <= 31 && backEndDti <= 43
            ? (isEs ? 'Elegible' : 'Eligible')
            : (isEs ? 'No elegible' : 'Not eligible'),
      ],
      [
        'VA / USDA',
        isEs ? 'Front flexible, Back ≤ 41%' : 'Flexible front, Back ≤ 41%',
        backEndDti <= 41
            ? (isEs ? 'Elegible' : 'Eligible')
            : (isEs ? 'No elegible' : 'Not eligible'),
      ],
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppTextSize.xs,
                          color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tIncome, [
                  _row2(tAnnualIncome, _usd0.format(annualIncome)),
                  _row2(tMonthlyIncome, _usd2.format(monthlyIncome)),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tDebts, [
                  _row2(tPITI, _usd2.format(piti), bold: true),
                  if (carPayment > 0) _row2(tCar, _usd2.format(carPayment)),
                  if (studentLoans > 0)
                    _row2(tStudent, _usd2.format(studentLoans)),
                  if (creditCards > 0)
                    _row2(tCards, _usd2.format(creditCards)),
                  if (otherDebts > 0)
                    _row2(tOther, _usd2.format(otherDebts)),
                  pw.Divider(color: PdfColors.grey300, height: 6),
                  _row2(
                    isEs
                        ? 'Total deudas + vivienda'
                        : 'Total debt + housing',
                    _usd2.format(piti +
                        carPayment +
                        studentLoans +
                        creditCards +
                        otherDebts),
                    bold: true,
                  ),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tDtiResults, [
                  _row2(tFrontEnd, '${frontEndDti.toStringAsFixed(1)}%',
                      bold: true, color: frontColor),
                  _row2(
                    isEs ? 'Diagnóstico' : 'Verdict',
                    dtiVerdict(frontEndDti, 28, 36),
                    color: frontColor,
                  ),
                  pw.Divider(color: PdfColors.grey300, height: 6),
                  _row2(tBackEnd, '${backEndDti.toStringAsFixed(1)}%',
                      bold: true, color: backColor),
                  _row2(
                    isEs ? 'Diagnóstico' : 'Verdict',
                    dtiVerdict(backEndDti, 36, 43),
                    color: backColor,
                  ),
                  if (monthlyIncome > 0) ...[
                    pw.Divider(color: PdfColors.grey300, height: 6),
                    _row2(
                      isEs
                          ? 'Pago máx. hipoteca (28%)'
                          : 'Max mortgage pmt (28%)',
                      _usd2.format(monthlyIncome * 0.28),
                    ),
                  ],
                ]),
                pw.SizedBox(height: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      color: _navy,
                      child: pw.Text(tEligibility,
                          style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(AppSpacing.sm),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey300, width: 0.5)),
                      child: pw.TableHelper.fromTextArray(
                        headers: [
                          isEs ? 'Tipo' : 'Type',
                          isEs ? 'Criterio' : 'Criteria',
                          isEs ? 'Estado' : 'Status',
                        ],
                        data: eligData,
                        headerStyle: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white),
                        headerDecoration:
                            const pw.BoxDecoration(color: _navy),
                        cellStyle: const pw.TextStyle(fontSize: 8),
                        cellHeight: 14,
                        cellAlignments: {
                          0: pw.Alignment.centerLeft,
                          1: pw.Alignment.centerLeft,
                          2: pw.Alignment.center,
                        },
                        rowDecoration:
                            const pw.BoxDecoration(color: PdfColors.white),
                        oddRowDecoration: pw.BoxDecoration(color: _light),
                        border: pw.TableBorder.all(
                            color: PdfColors.grey300, width: 0.5),
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── FHA PDF export ────────────────────────────────────────────────────────

  static Future<void> exportFha(
    BuildContext context, {
    required double homePrice,
    required double downPct,
    required double annualRatePct,
    required int termYears,
    required int creditScore,
    required double baseLoan,
    required double upfrontMip,
    required double loan,
    required double annualMipRate,
    required double monthlyMip,
    required double pAndI,
    required double monthlyTax,
    required double monthlyIns,
    required double totalMonthly,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildFhaPdf(_FhaPdfParams(
        homePrice: homePrice, downPct: downPct, annualRatePct: annualRatePct,
        termYears: termYears, creditScore: creditScore, baseLoan: baseLoan,
        upfrontMip: upfrontMip, loan: loan, annualMipRate: annualMipRate,
        monthlyMip: monthlyMip, pAndI: pAndI, monthlyTax: monthlyTax,
        monthlyIns: monthlyIns, totalMonthly: totalMonthly, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_FHA_${homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildFhaPage({
    required double homePrice,
    required double downPct,
    required double annualRatePct,
    required int termYears,
    required int creditScore,
    required double baseLoan,
    required double upfrontMip,
    required double loan,
    required double annualMipRate,
    required double monthlyMip,
    required double pAndI,
    required double monthlyTax,
    required double monthlyIns,
    required double totalMonthly,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Cálculo de Préstamo FHA' : 'FHA Loan Calculation';
    final tInputs = isEs ? 'DATOS DE ENTRADA' : 'INPUTS';
    final tHomePrice = isEs ? 'Precio de la vivienda' : 'Home Price';
    final tDown = isEs ? 'Pago inicial' : 'Down Payment';
    final tRate =
        isEs ? 'Tasa de interés (efectiva)' : 'Interest Rate (effective)';
    final tTerm = isEs ? 'Plazo' : 'Loan Term';
    final tYears = isEs ? 'años' : 'years';
    final tCreditScore = isEs ? 'Puntaje crediticio' : 'Credit Score';
    final tLoanDetails =
        isEs ? 'DETALLES DEL PRÉSTAMO FHA' : 'FHA LOAN DETAILS';
    final tBaseLoan = isEs ? 'Monto base del préstamo' : 'Base Loan Amount';
    final tUpfrontMip = isEs ? 'MIP inicial (1.75%)' : 'Upfront MIP (1.75%)';
    final tLoanWithMip =
        isEs ? 'Préstamo total financiado' : 'Total Financed Loan';
    final tAnnualMip = isEs ? 'MIP anual' : 'Annual MIP Rate';
    final tMonthly = isEs ? 'PAGO MENSUAL' : 'MONTHLY PAYMENT';
    final tPI = isEs ? 'Capital + Interés' : 'P & I';
    final tMonthlyMip = isEs ? 'MIP mensual' : 'Monthly MIP';
    final tTax = isEs ? 'Impuesto predial' : 'Property Tax';
    final tIns = isEs ? 'Seguro' : 'Insurance';
    final tTotal = isEs ? 'Pago total mensual' : 'Total Monthly Payment';
    final downAmount = homePrice * downPct / 100.0;
    final ltv = homePrice > 0 ? (baseLoan / homePrice) * 100.0 : 0.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppTextSize.xs,
                          color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tInputs, [
                  _row2(tHomePrice, _usd0.format(homePrice)),
                  _row2(
                    tDown,
                    '${_usd0.format(downAmount)} (${downPct.toStringAsFixed(1)}%)',
                  ),
                  _row2(tRate, '${annualRatePct.toStringAsFixed(2)}%'),
                  _row2(tTerm, '$termYears $tYears'),
                  _row2(tCreditScore, creditScore.toString()),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tLoanDetails, [
                  _row2(tBaseLoan, _usd0.format(baseLoan)),
                  _row2(tUpfrontMip, _usd0.format(upfrontMip),
                      color: PdfColors.orange700),
                  _row2(tLoanWithMip, _usd0.format(loan), bold: true),
                  _row2('LTV', '${ltv.toStringAsFixed(1)}%'),
                  _row2(tAnnualMip,
                      '${(annualMipRate * 100).toStringAsFixed(2)}%'),
                ]),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _sectionBox(tMonthly, [
                _row2(tPI, _usd2.format(pAndI)),
                _row2(tMonthlyMip, _usd2.format(monthlyMip),
                    color: PdfColors.orange700),
                _row2(tTax, _usd2.format(monthlyTax)),
                _row2(tIns, _usd2.format(monthlyIns)),
                pw.Divider(color: PdfColors.grey300, height: 6),
                _row2(tTotal, _usd2.format(totalMonthly),
                    bold: true, color: _navy),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColor(0.94, 0.96, 0.99),
            border: pw.Border.all(color: _navy, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            isEs
                ? 'FHA exige mínimo 3.5% de pago inicial. El MIP inicial se financia en el préstamo. MIP anual: 0.55% si LTV > 90%, 0.50% si LTV ≤ 90%.'
                : 'FHA requires 3.5% minimum down. Upfront MIP is financed into the loan. Annual MIP: 0.55% if LTV > 90%, 0.50% if LTV ≤ 90%.',
            style:
                const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── HELOC PDF export ──────────────────────────────────────────────────────

  static Future<void> exportHeloc(
    BuildContext context, {
    required double homeValue,
    required double mortgageBalance,
    required double maxLtv,
    required double drawAmount,
    required double rate,
    required int drawPeriod,
    required int repaymentPeriod,
    required double availableEquity,
    required double monthlyInterestOnly,
    required double monthlyRepayment,
    required double totalCost,
    bool isEs = false,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildHelocPdf(_HelocPdfParams(
        homeValue: homeValue, mortgageBalance: mortgageBalance, maxLtv: maxLtv,
        drawAmount: drawAmount, rate: rate, drawPeriod: drawPeriod,
        repaymentPeriod: repaymentPeriod, availableEquity: availableEquity,
        monthlyInterestOnly: monthlyInterestOnly, monthlyRepayment: monthlyRepayment,
        totalCost: totalCost, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_HELOC_${homeValue.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildHelocPage({
    required double homeValue,
    required double mortgageBalance,
    required double maxLtv,
    required double drawAmount,
    required double rate,
    required int drawPeriod,
    required int repaymentPeriod,
    required double availableEquity,
    required double monthlyInterestOnly,
    required double monthlyRepayment,
    required double totalCost,
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final tReport = isEs ? 'Calculadora HELOC' : 'HELOC Calculator';
    final tInputs = isEs ? 'DATOS DE ENTRADA' : 'INPUTS';
    final tHomeValue = isEs ? 'Valor de la vivienda' : 'Home Value';
    final tMortgageBal = isEs ? 'Saldo hipotecario' : 'Mortgage Balance';
    final tMaxLtv = isEs ? 'LTV máximo' : 'Max LTV';
    final tDrawAmount = isEs ? 'Monto a retirar' : 'Draw Amount';
    final tRate = isEs ? 'Tasa de interés' : 'Interest Rate';
    final tDrawPeriod = isEs ? 'Período de retiro' : 'Draw Period';
    final tRepayPeriod = isEs ? 'Período de repago' : 'Repayment Period';
    final tYears = isEs ? 'años' : 'years';
    final tResults = isEs ? 'RESULTADOS' : 'RESULTS';
    final tAvailEquity = isEs ? 'Capital disponible' : 'Available Equity';
    final tCurrentLtv = isEs ? 'LTV actual' : 'Current LTV';
    final tLtvAfterDraw = isEs ? 'LTV después del retiro' : 'LTV after Draw';
    final tDrawPayment =
        isEs ? 'Pago retiro (solo interés)' : 'Draw Phase Payment (interest-only)';
    final tRepayPayment = isEs ? 'Pago de repago' : 'Repayment Phase Payment';
    final tTotalCost = isEs ? 'Costo total HELOC' : 'Total HELOC Cost';
    final tTotalInterest = isEs ? 'Interés total estimado' : 'Est. Total Interest';
    final tVerdictSection = isEs ? 'ANÁLISIS' : 'ANALYSIS';
    final currentLtv =
        homeValue > 0 ? mortgageBalance / homeValue * 100 : 0.0;
    final ltvAfterDraw =
        homeValue > 0 ? (mortgageBalance + drawAmount) / homeValue * 100 : 0.0;
    final drawExceedsEquity = drawAmount > availableEquity;
    final totalInterest = totalCost - drawAmount;
    final verdictOk = !drawExceedsEquity && ltvAfterDraw <= 90.0;
    final verdictColor =
        verdictOk ? PdfColor(0.13, 0.55, 0.33) : PdfColors.red700;
    final verdictBg = verdictOk
        ? PdfColor(0.90, 0.97, 0.92)
        : PdfColor(0.99, 0.93, 0.93);
    final verdictText = drawExceedsEquity
        ? (isEs
            ? 'Retiro excede el capital disponible'
            : 'Draw exceeds available equity')
        : ltvAfterDraw > 90.0
            ? (isEs
                ? 'LTV > 90% — la mayoría de prestamistas no aprueban'
                : 'LTV > 90% — most lenders will not approve')
            : (isEs
                ? 'El capital de tu vivienda soporta este retiro'
                : 'Your home equity supports this draw');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                          fontSize: AppTextSize.xs,
                          color: PdfColors.grey700)),
                ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(
            height: 2,
            color: _navy,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _sectionBox(tInputs, [
                _row2(tHomeValue, _usd0.format(homeValue)),
                _row2(tMortgageBal, _usd0.format(mortgageBalance)),
                _row2(tMaxLtv, '${maxLtv.toStringAsFixed(0)}%'),
                _row2(tDrawAmount, _usd0.format(drawAmount)),
                _row2(tRate, '${rate.toStringAsFixed(2)}%'),
                _row2(tDrawPeriod, '$drawPeriod $tYears'),
                _row2(tRepayPeriod, '$repaymentPeriod $tYears'),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(children: [
                _sectionBox(tResults, [
                  _row2(tAvailEquity, _usd0.format(availableEquity),
                      bold: true, color: PdfColor(0.05, 0.58, 0.53)),
                  _row2(tCurrentLtv, '${currentLtv.toStringAsFixed(1)}%'),
                  _row2(tLtvAfterDraw,
                      '${ltvAfterDraw.toStringAsFixed(1)}%',
                      color: ltvAfterDraw > 90
                          ? PdfColors.red700
                          : PdfColors.black),
                  pw.Divider(color: PdfColors.grey300, height: 6),
                  _row2(tDrawPayment,
                      '${_usd2.format(monthlyInterestOnly)}/mo'),
                  _row2(tRepayPayment,
                      '${_usd2.format(monthlyRepayment)}/mo'),
                  pw.Divider(color: PdfColors.grey300, height: 6),
                  _row2(tTotalInterest, _usd0.format(totalInterest)),
                  _row2(tTotalCost, _usd0.format(totalCost),
                      bold: true, color: PdfColors.orange700),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(tVerdictSection, [
                  pw.SizedBox(height: 4),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: verdictBg,
                      border:
                          pw.Border.all(color: verdictColor, width: 1),
                      borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4)),
                    ),
                    child: pw.Text(verdictText,
                        style: pw.TextStyle(
                            fontSize: AppTextSize.xs,
                            fontWeight: pw.FontWeight.bold,
                            color: verdictColor)),
                  ),
                ]),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
    );
  }

  // ── Unlock sheet entry point ──────────────────────────────────────────────

  /// Shows the standard PaywallHard. If the user gets premium (IAP or rewarded
  /// ad 60-min access), the export proceeds immediately after dismissal.
  static Future<void> showUnlockOrPay(
    BuildContext context,
    Future<void> Function() onExport,
  ) async {
    if (freemiumService.hasFullAccess) {
      await onExport();
      return;
    }
    final isEs = isSpanishNotifier.value;
    await PaywallHard.show(
      context,
      isSpanish: isEs,
      features: isEs
          ? ['Exportar PDF completo', 'Sin anuncios', 'Historial ilimitado', 'Acceso completo']
          : ['Full PDF export', 'No ads', 'Unlimited history', 'Full access'],
    );
  }

  // ── PMI Simple PDF export (pmi_screen) ───────────────────────────────────

  static Future<void> exportPmiSimple(
    BuildContext context, {
    required double homePrice,
    required double downPct,
    required double loanAmount,
    required double ltv,
    required double monthlyPmi,
    required int? dropMonth,
    required double totalPmiCost,
    required bool isEs,
  }) async {
    final pdfBytes = await Isolate.run(
      () => _buildPmiSimplePdf(_PmiSimplePdfParams(
        homePrice: homePrice, downPct: downPct, loanAmount: loanAmount,
        ltv: ltv, monthlyPmi: monthlyPmi, dropMonth: dropMonth,
        totalPmiCost: totalPmiCost, isEs: isEs,
      )),
    );
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/MortgageUS_PMI_${homePrice.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildPmiSimplePage({
    required double homePrice,
    required double downPct,
    required double loanAmount,
    required double ltv,
    required double monthlyPmi,
    required int? dropMonth,
    required double totalPmiCost,
    required bool isEs,
  }) {
    final now = DateTime.now();
    final downAmt = homePrice * downPct / 100.0;
    final annualPmi = monthlyPmi * 12;

    final tReport = isEs ? 'Calculadora PMI' : 'PMI Calculator';
    final tLoanInfo = isEs ? 'DETALLES DEL PRÉSTAMO' : 'LOAN DETAILS';
    final tHomePrice = isEs ? 'Precio de la vivienda' : 'Home Price';
    final tDownPayment = isEs ? 'Pago inicial' : 'Down Payment';
    final tLoanAmount = isEs ? 'Monto del préstamo' : 'Loan Amount';
    final tLtv = 'LTV Ratio';
    final tPmiSection = isEs ? 'ANÁLISIS PMI' : 'PMI ANALYSIS';
    final tPmiAnnualRate = isEs ? 'Tasa PMI anual (estimada)' : 'PMI Annual Rate (est.)';
    final tMonthlyPmi = isEs ? 'PMI mensual estimado' : 'Est. Monthly PMI';
    final tAnnualPmi = isEs ? 'PMI anual estimado' : 'Est. Annual PMI';
    final tAutoCancel = isEs ? 'Cancelación automática (LTV 78%)' : 'Auto-cancel (LTV 78%)';
    final tTotalPmi = isEs ? 'Costo total PMI hasta cancelación' : 'Total PMI cost until auto-cancel';
    final tNote = isEs ? 'Nota' : 'Note';
    final tNoteText = isEs
        ? 'PMI puede cancelarse a solicitud al alcanzar 80% LTV; cancelación obligatoria a 78% LTV.'
        : 'PMI may be cancelled on request at 80% LTV; mandatory cancellation at 78% LTV.';

    String fmtMonths(int? m) {
      if (m == null) return isEs ? 'N/A' : 'N/A';
      if (m == 0) return isEs ? 'Ya alcanzado' : 'Already reached';
      return '${m ~/ 12}${isEs ? ' años' : ' yrs'} ${m % 12}${isEs ? ' meses' : ' mo'}';
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('MortgageUS',
                  style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.Text(tReport,
                  style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700)),
            ]),
            pw.Text(_dateLong(isEs).format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
        pw.Container(height: 2, color: _navy, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _sectionBox(tLoanInfo, [
                _row2(tHomePrice, _usd0.format(homePrice)),
                _row2(tDownPayment, '${_usd0.format(downAmt)} (${downPct.toStringAsFixed(1)}%)'),
                _row2(tLoanAmount, _usd0.format(loanAmount)),
                _row2(tLtv, '${ltv.toStringAsFixed(1)}%',
                    color: ltv > 95 ? PdfColors.red700 : ltv > 90 ? PdfColor(0.80, 0.45, 0.0) : _navy),
              ]),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: _sectionBox(tPmiSection, [
                _row2(tPmiAnnualRate, '0.80%'),
                _row2(tMonthlyPmi, _usd2.format(monthlyPmi), bold: true, color: _gold),
                _row2(tAnnualPmi, _usd0.format(annualPmi)),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Divider(color: PdfColors.grey300, height: 6)),
                _row2(tAutoCancel, fmtMonths(dropMonth), bold: true),
                if (dropMonth != null)
                  _row2(tTotalPmi, _usd0.format(totalPmiCost)),
                _row2(tNote, tNoteText, small: true),
              ]),
            ),
          ],
        ),
        pw.Spacer(),
        _footerNote(isEs: isEs),
      ],
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


import 'dart:math';
import '../models/amortization_entry.dart';
import '../models/extra_payment_result.dart';
import '../models/loan_type.dart';
import '../models/mortgage_input.dart';
import '../models/mortgage_result.dart';
import '../models/refinance_result.dart';
import '../../core/constants/mortgage_constants.dart';

class MortgageCalculator {

  // ── P&I monthly payment ───────────────────────────────────────────────────

  /// Calculate monthly principal + interest payment.
  /// Formula: P × r(1+r)^n / ((1+r)^n - 1)
  /// r = monthly rate, n = total months
  static double calcMonthlyPayment({
    required double loanAmount,
    required double annualRatePct,
    required int    termYears,
  }) {
    if (loanAmount < 0)  throw ArgumentError('Loan amount must be >= 0');
    if (annualRatePct < 0) throw ArgumentError('Rate must be >= 0');
    if (termYears <= 0)    throw ArgumentError('Term must be > 0');

    if (loanAmount == 0) return 0.0;

    final n = termYears * 12;
    final r = annualRatePct / 100.0 / 12.0;

    if (r == 0.0) return loanAmount / n;

    final p = pow(1 + r, n).toDouble();
    return loanAmount * r * p / (p - 1);
  }

  // ── Full amortization schedule ────────────────────────────────────────────

  static List<AmortizationEntry> buildSchedule({
    required double   loanAmount,
    required double   annualRatePct,
    required int      termYears,
    required double   homePrice,
    required double   pmiAnnualRatePct,
    required DateTime startDate,
  }) {
    if (loanAmount < 0 || annualRatePct < 0 || termYears <= 0) {
      throw ArgumentError('Invalid inputs for amortization');
    }

    final payment = calcMonthlyPayment(
      loanAmount: loanAmount,
      annualRatePct: annualRatePct,
      termYears: termYears,
    );
    final r = annualRatePct / 100.0 / 12.0;
    final n = termYears * 12;

    final entries = <AmortizationEntry>[];
    double balance        = loanAmount;
    double cumInterest    = 0.0;
    double cumPrincipal   = 0.0;
    bool   pmiActive      = (homePrice > 0) &&
        (loanAmount / homePrice) > MortgageConstants.pmiLtvThreshold; // activate at >80% LTV
    bool   pmiEverDropped = false;

    for (int month = 1; month <= n; month++) {
      final interest  = balance * r;
      var   principal = payment - interest;

      // Last payment: clear remaining balance (floating point cleanup)
      if (month == n) principal = balance;

      final newBalance = (balance - principal).clamp(0.0, double.infinity);

      // PMI: check if LTV crossed 78% threshold
      double pmiAmt  = 0.0;
      bool   dropped = false;
      if (pmiActive && homePrice > 0) {
        final ltv = newBalance / homePrice;
        if (ltv <= MortgageConstants.pmiAutoCancelLtv) {
          pmiActive      = false;
          dropped        = !pmiEverDropped;
          pmiEverDropped = true;
        } else {
          pmiAmt = (loanAmount * pmiAnnualRatePct / 100.0) / 12.0;
        }
      }

      cumInterest  += interest;
      cumPrincipal += principal;

      final entryDate = DateTime(
        startDate.year,
        startDate.month + month - 1,
      );

      entries.add(AmortizationEntry(
        month:               month,
        date:                entryDate,
        payment:             payment,
        principal:           principal,
        interest:            interest,
        balance:             newBalance,
        cumulativeInterest:  cumInterest,
        cumulativePrincipal: cumPrincipal,
        pmiAmount:           pmiAmt,
        pmiDropped:          dropped,
      ));

      balance = newBalance;
      if (balance <= 0.001) break;
    }

    return entries;
  }

  // ── Full result with PITI ─────────────────────────────────────────────────

  static MortgageResult calculate(MortgageInput input) {
    final loan = input.loanAmount;
    if (input.homePrice <= 0) throw ArgumentError('Home price must be > 0');
    if (loan < 0)             throw ArgumentError('Loan amount must be >= 0');
    if (input.annualRatePct < 0) throw ArgumentError('Rate must be >= 0');
    if (input.termYears <= 0)    throw ArgumentError('Term must be > 0');

    final pi = calcMonthlyPayment(
      loanAmount: loan,
      annualRatePct: input.annualRatePct,
      termYears: input.termYears,
    );

    final propertyTaxMonthly = (input.homePrice * input.propertyTaxRatePct / 100.0) / 12.0;
    final insuranceMonthly   = input.homeInsuranceAnnual / 12.0;
    final ltv                = input.ltv;

    // PMI
    final hasPmi = ltv > 80.0 && input.loanType != LoanType.va;
    final pmiMonthly = hasPmi
        ? (loan * input.pmiAnnualRatePct / 100.0) / 12.0
        : 0.0;

    final schedule = buildSchedule(
      loanAmount:       loan,
      annualRatePct:    input.annualRatePct,
      termYears:        input.termYears,
      homePrice:        input.homePrice,
      pmiAnnualRatePct: input.pmiAnnualRatePct,
      startDate:        input.startDate,
    );

    final totalInterest = schedule.last.cumulativeInterest;
    final totalCost     = loan + totalInterest;
    final payoffDate    = schedule.last.date;

    // Find PMI drop month
    int? pmiDropMonth;
    for (final e in schedule) {
      if (e.pmiDropped) { pmiDropMonth = e.month; break; }
    }

    // Decompose PI for monthly breakdown
    // First month interest portion:
    final r = input.annualRatePct / 100.0 / 12.0;
    final firstInterest  = r > 0 ? loan * r : 0.0;
    final firstPrincipal = pi - firstInterest;

    return MortgageResult(
      loanAmount:   loan,
      monthly: MonthlyBreakdown(
        principal:     firstPrincipal,
        interest:      firstInterest,
        propertyTax:   propertyTaxMonthly,
        homeInsurance: insuranceMonthly,
        hoa:           input.hoaMonthly,
        pmi:           pmiMonthly,
      ),
      totalInterest: totalInterest,
      totalCost:     totalCost,
      payoffDate:    payoffDate,
      currentLtv:    ltv,
      isJumbo:       input.isJumbo,
      hasPmi:        hasPmi,
      pmiDropMonth:  pmiDropMonth,
      schedule:      schedule,
    );
  }

  // ── Extra payments ────────────────────────────────────────────────────────

  static ExtraPaymentResult calcExtraPayments({
    required double loanAmount,
    required double annualRatePct,
    required int    termYears,
    required double extraMonthly,
    double extraAnnual  = 0.0,
    double lumpSum      = 0.0,
    int    lumpSumMonth = 0,
  }) {
    if (loanAmount <= 0)   throw ArgumentError('Loan amount must be > 0');
    if (annualRatePct < 0) throw ArgumentError('Rate must be >= 0');
    if (termYears <= 0)    throw ArgumentError('Term must be > 0');

    final basePayment = calcMonthlyPayment(
      loanAmount: loanAmount,
      annualRatePct: annualRatePct,
      termYears: termYears,
    );
    final r = annualRatePct / 100.0 / 12.0;
    final n = termYears * 12;

    // Baseline total interest
    double baseCumInterest = 0.0;
    double bal = loanAmount;
    for (int m = 1; m <= n; m++) {
      final interest  = bal * r;
      final principal = m == n ? bal : (basePayment - interest);
      baseCumInterest += interest;
      bal = (bal - principal).clamp(0, double.infinity);
      if (bal <= 0.001) break;
    }

    // With extra payments
    double extraCumInterest = 0.0;
    int    payoffMonth      = n;
    bal = loanAmount;
    for (int m = 1; m <= n; m++) {
      final interest = bal * r;
      var   extra    = extraMonthly;
      if (m % 12 == 0) extra += extraAnnual;
      if (m == lumpSumMonth) extra += lumpSum;

      var principal = (basePayment - interest) + extra;
      if (principal > bal) principal = bal;

      extraCumInterest += interest;
      bal = (bal - principal).clamp(0, double.infinity);

      if (bal <= 0.001) {
        payoffMonth = m;
        break;
      }
    }

    return ExtraPaymentResult(
      originalPayoffMonths:  n,
      newPayoffMonths:       payoffMonth,
      monthsSaved:           n - payoffMonth,
      originalTotalInterest: baseCumInterest,
      newTotalInterest:      extraCumInterest,
      interestSaved:         baseCumInterest - extraCumInterest,
    );
  }

  // ── Refinance ─────────────────────────────────────────────────────────────

  static RefinanceResult calcRefinance({
    required double currentBalance,
    required double currentRatePct,
    required int    currentYearsRemaining,
    required double newRatePct,
    required int    newTermYears,
    required double closingCosts,
    double cashOut = 0.0,
  }) {
    if (currentBalance <= 0)          throw ArgumentError('Balance must be > 0');
    if (currentRatePct < 0 || newRatePct < 0) throw ArgumentError('Rates must be >= 0');
    if (currentYearsRemaining <= 0 || newTermYears <= 0) throw ArgumentError('Terms must be > 0');

    final oldPayment = calcMonthlyPayment(
      loanAmount:    currentBalance,
      annualRatePct: currentRatePct,
      termYears:     currentYearsRemaining,
    );
    final newLoanAmount = currentBalance + cashOut;
    final newPayment = calcMonthlyPayment(
      loanAmount:    newLoanAmount,
      annualRatePct: newRatePct,
      termYears:     newTermYears,
    );

    final monthlySavings = oldPayment - newPayment;
    final breakEvenMonths = monthlySavings > 0
        ? (closingCosts / monthlySavings).ceil()
        : 999999;

    final newTotalMonths = newTermYears * 12;
    final totalSavings   = (monthlySavings * newTotalMonths.toDouble()) - closingCosts;

    // Makes sense if break-even < 7 years (84 months)
    final makesSense = breakEvenMonths <= 84 && monthlySavings > 0;

    return RefinanceResult(
      oldMonthlyPayment:    oldPayment,
      newMonthlyPayment:    newPayment,
      monthlySavings:       monthlySavings,
      breakEvenMonths:      breakEvenMonths,
      totalSavingsOverLife: totalSavings,
      refinanceMakesSense:  makesSense,
    );
  }

  // ── PMI monthly ───────────────────────────────────────────────────────────

  static double calcPmiMonthly({
    required double loanAmount,
    required double homePrice,
    required double pmiAnnualRatePct,
  }) {
    if (homePrice <= 0) return 0.0;
    final ltv = loanAmount / homePrice;
    if (ltv <= MortgageConstants.pmiLtvThreshold) return 0.0;
    return (loanAmount * pmiAnnualRatePct / 100.0) / 12.0;
  }
}

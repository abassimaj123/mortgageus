import 'dart:math';
import '../models/amortization_entry.dart';
import '../models/arm_result.dart';
import '../models/affordability_result.dart';
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
    bool              pmiNeverDrops = false,
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
        if (!pmiNeverDrops && ltv <= MortgageConstants.pmiAutoCancelLtv) {
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

    final isUsda = input.loanType == LoanType.usda;
    final isVa   = input.loanType == LoanType.va;

    // USDA: 1% upfront guarantee fee is financed into the loan
    final effectiveLoan = isUsda ? loan * 1.01 : loan;

    final pi = calcMonthlyPayment(
      loanAmount: effectiveLoan,
      annualRatePct: input.annualRatePct,
      termYears: input.termYears,
    );

    final propertyTaxMonthly = (input.homePrice * input.propertyTaxRatePct / 100.0) / 12.0;
    final insuranceMonthly   = input.homeInsuranceAnnual / 12.0;
    final ltv                = input.ltv;

    // PMI / USDA annual fee (0.35% — never drops)
    final hasPmi     = isUsda || (ltv > 80.0 && !isVa);
    final pmiRate    = isUsda ? 0.35 : input.pmiAnnualRatePct;
    final pmiMonthly = hasPmi ? (effectiveLoan * pmiRate / 100.0) / 12.0 : 0.0;

    final schedule = buildSchedule(
      loanAmount:       effectiveLoan,
      annualRatePct:    input.annualRatePct,
      termYears:        input.termYears,
      homePrice:        input.homePrice,
      pmiAnnualRatePct: pmiRate,
      pmiNeverDrops:    isUsda,
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

    // Stress test: +2% rate scenario
    final stressRate = input.annualRatePct + 2.0;
    final stressMonthly = calcMonthlyPayment(
      loanAmount: effectiveLoan,
      annualRatePct: stressRate,
      termYears: input.termYears,
    );

    // First month PI decomposition using effectiveLoan
    final rEff = input.annualRatePct / 100.0 / 12.0;
    final firstInterestEff  = rEff > 0 ? effectiveLoan * rEff : 0.0;
    final firstPrincipalEff = pi - firstInterestEff;

    return MortgageResult(
      loanAmount:   effectiveLoan,
      monthly: MonthlyBreakdown(
        principal:     firstPrincipalEff,
        interest:      firstInterestEff,
        propertyTax:   propertyTaxMonthly,
        homeInsurance: insuranceMonthly,
        hoa:           input.hoaMonthly,
        pmi:           pmiMonthly,
      ),
      totalInterest:     totalInterest,
      totalCost:         totalCost,
      payoffDate:        payoffDate,
      currentLtv:        ltv,
      isJumbo:           input.isJumbo,
      hasPmi:            hasPmi,
      isUsda:            isUsda,
      pmiDropMonth:      pmiDropMonth,
      schedule:          schedule,
      stressTestRate:    stressRate,
      stressTestMonthly: stressMonthly,
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

  // ── ARM (Adjustable Rate Mortgage) ────────────────────────────────────────

  /// Compare ARM (fixedYears/1) against equivalent fixed-rate 30yr loan.
  /// Phase 1: [0, fixedMonths) — payment at initialRatePct on full term
  /// Phase 2: [fixedMonths, totalTermYears*12) — payment resets on remaining balance at adjustedRatePct
  static ARMResult calcARM({
    required double loanAmount,
    required double initialRatePct,
    required int    fixedYears,
    required double adjustedRatePct,
    required int    totalTermYears,
  }) {
    if (loanAmount <= 0)    throw ArgumentError('Loan amount must be > 0');
    if (initialRatePct < 0 || adjustedRatePct < 0) throw ArgumentError('Rates must be >= 0');
    if (fixedYears <= 0 || totalTermYears <= fixedYears) {
      throw ArgumentError('Invalid term split');
    }

    final fixedMonths     = fixedYears * 12;
    final remainingYears  = totalTermYears - fixedYears;
    final totalMonths     = totalTermYears * 12;

    // ARM phase-1 payment: amortized over full term at initial rate
    final payment1 = calcMonthlyPayment(
      loanAmount:    loanAmount,
      annualRatePct: initialRatePct,
      termYears:     totalTermYears,
    );

    // Amortize phase 1 to find balance at reset
    final r1 = initialRatePct / 100.0 / 12.0;
    double balance = loanAmount;
    double armInterest = 0.0;
    for (int m = 1; m <= fixedMonths; m++) {
      final interest  = balance * r1;
      final principal = (payment1 - interest).clamp(0.0, balance);
      armInterest += interest;
      balance     -= principal;
      if (balance < 0.001) { balance = 0; break; }
    }
    final balanceAtReset = balance;

    // ARM phase-2 payment: amortized on remaining balance at adjusted rate
    double payment2 = 0.0;
    if (balanceAtReset > 0.001) {
      payment2 = calcMonthlyPayment(
        loanAmount:    balanceAtReset,
        annualRatePct: adjustedRatePct,
        termYears:     remainingYears,
      );
    }

    // Amortize phase 2
    final r2 = adjustedRatePct / 100.0 / 12.0;
    balance = balanceAtReset;
    for (int m = 1; m <= remainingYears * 12; m++) {
      final interest  = balance * r2;
      final principal = (payment2 - interest).clamp(0.0, balance);
      armInterest += interest;
      balance     -= principal;
      if (balance < 0.001) break;
    }
    final armTotalInterest = armInterest;
    final armTotalCost     = loanAmount + armTotalInterest;

    // Fixed 30yr baseline (at initial rate for apples-to-apples comparison)
    final fixedPayment = calcMonthlyPayment(
      loanAmount:    loanAmount,
      annualRatePct: initialRatePct,
      termYears:     totalTermYears,
    );
    double fixedInterestTotal = 0.0;
    double fixedBal = loanAmount;
    for (int m = 1; m <= totalMonths; m++) {
      final interest  = fixedBal * r1;
      final principal = (fixedPayment - interest).clamp(0.0, fixedBal);
      fixedInterestTotal += interest;
      fixedBal -= principal;
      if (fixedBal < 0.001) break;
    }

    // Break-even: month when ARM cumulative payments >= fixed cumulative payments
    // (relevant when ARM resets to higher rate)
    int? breakEvenMonths;
    if (payment2 > fixedPayment) {
      double armCum   = 0;
      double fixedCum = 0;
      for (int m = 1; m <= totalMonths; m++) {
        armCum   += m <= fixedMonths ? payment1 : payment2;
        fixedCum += fixedPayment;
        if (armCum >= fixedCum && m > fixedMonths) {
          breakEvenMonths = m;
          break;
        }
      }
    }

    return ARMResult(
      payment1:            payment1,
      payment2:            payment2,
      balanceAtReset:      balanceAtReset,
      totalInterest:       armTotalInterest,
      totalCost:           armTotalCost,
      fixedMonths:         fixedMonths,
      fixedPayment:        fixedPayment,
      fixedTotalInterest:  fixedInterestTotal,
      breakEvenMonths:     breakEvenMonths,
    );
  }

  // ── Affordability ─────────────────────────────────────────────────────────

  /// Returns max home price under two DTI thresholds (28% conservative, 43% standard).
  /// Binary search over home price until PITI fits inside the budget.
  static AffordabilityResult calcAffordability({
    required double annualIncome,
    required double monthlyDebts,
    required double downPayment,
    required double annualRatePct,
    required int    termYears,
    double propertyTaxRatePct  = 1.1,
    double homeInsuranceAnnual = 1750,
    double hoaMonthly          = 0,
  }) {
    if (annualIncome <= 0) throw ArgumentError('Income must be > 0');
    if (termYears <= 0)    throw ArgumentError('Term must be > 0');

    final monthlyGross = annualIncome / 12.0;

    // Conservative: front-end DTI 28% (PITI only, no debts)
    final maxPITI_conservative = monthlyGross * 0.28;
    final maxHomeCons = _solveMaxHomePrice(
      maxAllowablePITI: maxPITI_conservative,
      downPayment:       downPayment,
      annualRatePct:     annualRatePct,
      termYears:         termYears,
      propertyTaxRatePct:  propertyTaxRatePct,
      homeInsuranceAnnual: homeInsuranceAnnual,
      hoaMonthly:          hoaMonthly,
    );

    // Standard: back-end DTI 43% (PITI + all monthly debts)
    final maxPITI_standard = (monthlyGross * 0.43) - monthlyDebts;
    final maxHomeStd = maxPITI_standard > 0
        ? _solveMaxHomePrice(
            maxAllowablePITI: maxPITI_standard,
            downPayment:       downPayment,
            annualRatePct:     annualRatePct,
            termYears:         termYears,
            propertyTaxRatePct:  propertyTaxRatePct,
            homeInsuranceAnnual: homeInsuranceAnnual,
            hoaMonthly:          hoaMonthly,
          )
        : 0.0;

    // Build breakdown using the standard (higher) result
    final displayHome = maxHomeStd > 0 ? maxHomeStd : maxHomeCons;
    final displayLoan = (displayHome - downPayment).clamp(0.0, double.infinity);

    final pi  = displayLoan > 0
        ? calcMonthlyPayment(loanAmount: displayLoan, annualRatePct: annualRatePct, termYears: termYears)
        : 0.0;
    final tax = (displayHome * propertyTaxRatePct / 100.0) / 12.0;
    final ins = homeInsuranceAnnual / 12.0;
    final ltv = displayHome > 0 ? displayLoan / displayHome : 0.0;
    final pmi = ltv > 0.80
        ? (displayLoan * MortgageConstants.pmiDefaultAnnualRate) / 12.0
        : 0.0;

    return AffordabilityResult(
      maxHomePriceConservative: maxHomeCons,
      maxHomePriceStandard:     maxHomeStd,
      maxLoanConservative:      (maxHomeCons - downPayment).clamp(0.0, double.infinity),
      maxLoanStandard:          (maxHomeStd  - downPayment).clamp(0.0, double.infinity),
      monthlyPI:        pi,
      monthlyTax:       tax,
      monthlyInsurance: ins,
      monthlyPMI:       pmi,
      monthlyHOA:       hoaMonthly,
      totalMonthly:     pi + tax + ins + pmi + hoaMonthly,
      inputDownPayment: downPayment,
      monthlyGrossIncome: monthlyGross,
    );
  }

  static double _solveMaxHomePrice({
    required double maxAllowablePITI,
    required double downPayment,
    required double annualRatePct,
    required int    termYears,
    required double propertyTaxRatePct,
    required double homeInsuranceAnnual,
    required double hoaMonthly,
  }) {
    if (maxAllowablePITI <= 0) return 0.0;

    double lo = 0.0;
    double hi = 5000000.0; // $5M ceiling

    for (int i = 0; i < 60; i++) {
      final mid  = (lo + hi) / 2;
      final loan = (mid - downPayment).clamp(0.0, double.infinity);
      if (loan <= 0) { lo = mid; continue; }

      final pi  = calcMonthlyPayment(loanAmount: loan, annualRatePct: annualRatePct, termYears: termYears);
      final tax = (mid * propertyTaxRatePct / 100.0) / 12.0;
      final ins = homeInsuranceAnnual / 12.0;
      final ltv = loan / mid;
      final pmi = ltv > 0.80
          ? (loan * MortgageConstants.pmiDefaultAnnualRate) / 12.0
          : 0.0;
      final piti = pi + tax + ins + pmi + hoaMonthly;

      if (piti < maxAllowablePITI) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    return ((lo + hi) / 2).floorToDouble();
  }
}

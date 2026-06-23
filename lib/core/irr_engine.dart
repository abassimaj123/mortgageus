/// IRR Engine — investment return math for MortgageUS.
/// Ported from PropertyROISuite/lib/core/roi_engine.dart (IRR/NPV section only).
library;

import 'dart:math';

class IrrEngine {
  // ── IRR / NPV ─────────────────────────────────────────────────────────────

  /// IRR via Newton-Raphson. cashFlows[0] = initial outflow (negative).
  /// Returns percentage (e.g., 12.4 means 12.4%).
  static double irr(List<double> cashFlows) {
    if (cashFlows.length < 2) return 0;
    bool hasPositive = false, hasNegative = false;
    for (final cf in cashFlows) {
      if (cf > 0) hasPositive = true;
      if (cf < 0) hasNegative = true;
    }
    if (!hasPositive || !hasNegative) return 0;

    double rate = 0.1;
    for (int iter = 0; iter < 200; iter++) {
      double npvVal = 0, dnpv = 0;
      for (int t = 0; t < cashFlows.length; t++) {
        final disc = _powD(1 + rate, t);
        npvVal += cashFlows[t] / disc;
        if (t > 0) {
          dnpv -= t * cashFlows[t] / (disc * (1 + rate));
        }
      }
      if (dnpv.abs() < 1e-12) break;
      final newRate = rate - npvVal / dnpv;
      if ((newRate - rate).abs() < 1e-9) {
        rate = newRate;
        break;
      }
      rate = newRate.clamp(-0.999, 15.0);
    }
    return rate * 100;
  }

  /// NPV given a discount rate (%) and cash flow series. cashFlows[0] = year 0.
  static double npv(double discountRatePct, List<double> cashFlows) {
    double result = 0;
    final r = discountRatePct / 100;
    for (int t = 0; t < cashFlows.length; t++) {
      result += cashFlows[t] / _powD(1 + r, t);
    }
    return result;
  }

  /// Build a rental property cash flow series for IRR/NPV.
  /// cashFlows[0]      = −(downPayment + closingCosts)
  /// cashFlows[1..n-1] = annual net cash flow (rent − mortgage − expenses)
  /// cashFlows[n]      = annual cash flow + net sale proceeds
  ///
  /// [loanAmount]   — original loan principal (property price − down payment).
  /// [annualRatePct] — mortgage annual interest rate (e.g. 7.0 for 7%).
  /// [termMonths]   — loan term in months (e.g. 360 for 30 years).
  static List<double> buildRentalCashFlows({
    required double initialInvestment,
    required double annualCashFlow,
    required double propertyValue,
    required double appreciationPercent,
    required double annualMortgagePayment,
    required double loanAmount,
    required double annualRatePct,
    required int termMonths,
    int years = 10,
  }) {
    final flows = <double>[-initialInvestment.abs()];
    double value = propertyValue;

    // Pre-compute monthly payment for amortization-based remaining balance.
    final monthlyRate = annualRatePct / 12.0 / 100.0;
    final double monthlyPayment = (loanAmount > 0 && monthlyRate > 0)
        ? loanAmount *
            monthlyRate /
            (1 - pow(1 + monthlyRate, -termMonths))
        : (termMonths > 0 ? loanAmount / termMonths : 0.0);

    for (int y = 1; y <= years; y++) {
      value *= (1 + appreciationPercent / 100);
      if (y < years) {
        flows.add(annualCashFlow);
      } else {
        // Remaining loan balance at end of hold period via amortization formula.
        final n = y * 12; // months elapsed at sale
        final double remainingBalance;
        if (monthlyRate > 0 && loanAmount > 0) {
          remainingBalance = loanAmount * pow(1 + monthlyRate, n) -
              monthlyPayment *
                  (pow(1 + monthlyRate, n) - 1) /
                  monthlyRate;
        } else {
          // Zero-rate fallback: straight-line principal reduction.
          remainingBalance =
              (loanAmount - monthlyPayment * n).clamp(0.0, loanAmount);
        }
        final saleNet = value * 0.94 -
            remainingBalance.clamp(0.0, value * 0.94);
        flows.add(annualCashFlow + saleNet);
      }
    }
    return flows;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _powD(double base, int exp) {
    double r = 1.0;
    for (int i = 0; i < exp; i++) r *= base;
    return r;
  }
}

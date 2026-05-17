/// IRR Engine — investment return math for MortgageUS.
/// Ported from PropertyROISuite/lib/core/roi_engine.dart (IRR/NPV section only).
library;

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
  static List<double> buildRentalCashFlows({
    required double initialInvestment,
    required double annualCashFlow,
    required double propertyValue,
    required double appreciationPercent,
    required double annualMortgagePayment,
    int years = 10,
  }) {
    final flows = <double>[-initialInvestment.abs()];
    double value = propertyValue;
    double remainingLoan = propertyValue * 0.80;
    for (int y = 1; y <= years; y++) {
      value *= (1 + appreciationPercent / 100);
      remainingLoan -=
          annualMortgagePayment > 0 ? (annualMortgagePayment * 0.25) : 0;
      if (y < years) {
        flows.add(annualCashFlow);
      } else {
        final saleNet = value * 0.94 - remainingLoan.clamp(0, value * 0.94);
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

import 'package:calcwise_core/calcwise_core.dart';

/// Firebase Analytics wrapper for MortgageUS.
/// Common events (open, calculate, history, paywall, ads, purchase) are
/// inherited from CalcwiseAnalytics. Only MortgageUS-specific events live here.
class AnalyticsService extends CalcwiseAnalytics {
  AnalyticsService._() : super(appName: 'MortgageUS');
  static final AnalyticsService instance = AnalyticsService._();

  // ── Calculator (rich params — kept as override) ───────────────────────────

  Future<void> logCalculation({
    required double homePrice,
    required double downPct,
    required double ratePct,
    required int amortYears,
  }) =>
      log('calculate', {
        'home_price_bucket': _priceBucket(homePrice),
        'down_pct': downPct.toInt(),
        'rate_bucket': ratePct < 4
            ? '<4%'
            : ratePct < 6
                ? '4-6%'
                : '>6%',
        'amort_years': amortYears,
      });

  Future<void> logSave() => log('calculation_saved');

  // ── App-specific features ─────────────────────────────────────────────────

  Future<void> logExtraPaymentSimulated() => log('extra_payment_simulated');
  Future<void> logRefinanceSimulated() => log('refinance_simulated');
  Future<void> logComparatorUsed() => log('comparator_used');
  Future<void> logAffordabilityCalculated() => log('affordability_calculated');
  Future<void> logArmCalculated() => log('arm_calculated');
  Future<void> logPmiCalculated() => log('pmi_calculated');
  Future<void> logInvestmentReturnCalculated() =>
      log('investment_return_calculated');
  Future<void> logFhaCalculated() => log('fha_calculated');
  Future<void> logVaCalculated() => log('va_calculated');
  Future<void> logUsdaCalculated() => log('usda_calculated');
  Future<void> logPmiStandaloneCalculated() => log('pmi_standalone_calculated');
  Future<void> logPointsCalculated() => log('points_calculated');

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _priceBucket(double price) {
    if (price < 200000) return '<200k';
    if (price < 400000) return '200-400k';
    if (price < 600000) return '400-600k';
    if (price < 1000000) return '600k-1M';
    return '>1M';
  }
}

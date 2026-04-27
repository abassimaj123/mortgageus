import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase Analytics wrapper for MortgageUS.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _fa = FirebaseAnalytics.instance;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> logAppOpen() => _log('app_open');

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> logTabChanged(String tabName) => _log('tab_changed', {
    'tab': tabName, // calculator|schedule|comparator|affordability|tools
  });

  // ── Calculator ────────────────────────────────────────────────────────────

  Future<void> logCalculation({
    required double homePrice,
    required double downPct,
    required double ratePct,
    required int    amortYears,
  }) => _log('calculate', {
    'home_price_bucket': _priceBucket(homePrice),
    'down_pct':          downPct.toInt(),
    'rate_bucket':       ratePct < 4 ? '<4%' : ratePct < 6 ? '4-6%' : '>6%',
    'amort_years':       amortYears,
  });

  // ── Paywall ───────────────────────────────────────────────────────────────

  Future<void> logPaywallShown(String type) => _log('paywall_shown', {
    'type': type, // soft | hard
  });

  Future<void> logPurchaseStarted() => _log('purchase_started');

  Future<void> logPurchaseCompleted() async {
    await _log('purchase_completed');
    await _fa.logEvent(name: 'purchase', parameters: {
      'currency': 'USD',
      'value':    4.99,
      'items':    'premium_mortgage_us',
    });
  }

  Future<void> logPurchaseRestored() => _log('purchase_restored');

  Future<void> logPurchaseFailed()   => _log('purchase_failed');

  Future<void> logRewardedAdWatched() => _log('rewarded_ad_watched');

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> logLanguageChanged(String lang) => _log('language_changed', {
    'language': lang, // en | es
  });

  // ── Features ─────────────────────────────────────────────────────────────

  Future<void> logHistorySaved()           => _log('history_saved');
  Future<void> logPdfExported()            => _log('pdf_exported');
  Future<void> logExtraPaymentSimulated()  => _log('extra_payment_simulated');
  Future<void> logRefinanceSimulated()     => _log('refinance_simulated');
  Future<void> logComparatorUsed()         => _log('comparator_used');
  Future<void> logAffordabilityCalculated() => _log('affordability_calculated');
  Future<void> logArmCalculated()          => _log('arm_calculated');
  Future<void> logPmiCalculated()          => _log('pmi_calculated');

  // ── User property ─────────────────────────────────────────────────────────

  Future<void> setUserPremium(bool isPremium) =>
      _fa.setUserProperty(name: 'is_premium', value: isPremium ? 'true' : 'false');

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (kDebugMode) {
      debugPrint('[Analytics] $name ${params ?? ''}');
      return;
    }
    await _fa.logEvent(name: name, parameters: params);
  }

  String _priceBucket(double price) {
    if (price < 200000)  return '<200k';
    if (price < 400000)  return '200-400k';
    if (price < 600000)  return '400-600k';
    if (price < 1000000) return '600k-1M';
    return '>1M';
  }
}

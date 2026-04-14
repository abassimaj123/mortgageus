import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _analytics = FirebaseAnalytics.instance;

  Future<void> log(String event, {Map<String, Object>? params}) async {
    if (kDebugMode) debugPrint('[Analytics] $event ${params ?? ''}');
    await _analytics.logEvent(name: event, parameters: params);
  }

  Future<void> setScreen(String screenName) async {
    if (kDebugMode) debugPrint('[Analytics] screen: $screenName');
    await _analytics.logScreenView(screenName: screenName);
  }

  Future<void> logCalculation(String type) =>
      log('calculation', params: {'type': type});

  Future<void> logAdFreeUnlocked() => log('ad_free_unlocked');

  Future<void> logAdShown(String adType) =>
      log('ad_shown', params: {'ad_type': adType});
}

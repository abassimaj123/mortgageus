import 'package:flutter/foundation.dart';

// ── AnalyticsService ──────────────────────────────────────────────────────────
// Placeholder — wire Firebase Analytics once google-services.json is added.
// Usage: AnalyticsService.instance.log('event_name', params: {'key': 'value'})
//
// To activate:
//   1. Add firebase_analytics to pubspec.yaml
//   2. Initialize Firebase in main.dart (see firebase_options.dart)
//   3. Uncomment FirebaseAnalytics lines below

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  // final _analytics = FirebaseAnalytics.instance; // uncomment after Firebase setup

  Future<void> log(String event, {Map<String, Object>? params}) async {
    if (kDebugMode) {
      debugPrint('[Analytics] $event ${params ?? ''}');
    }
    // await _analytics.logEvent(name: event, parameters: params);
  }

  Future<void> setUserId(String id) async {
    // await _analytics.setUserId(id: id);
  }

  Future<void> setScreen(String screenName) async {
    if (kDebugMode) {
      debugPrint('[Analytics] screen: $screenName');
    }
    // await _analytics.logScreenView(screenName: screenName);
  }

  // Common events
  Future<void> logCalculation(String type) => log('calculation', params: {'type': type});
  Future<void> logShare()                  => log('share');
  Future<void> logAdShown(String adType)   => log('ad_shown', params: {'ad_type': adType});
}

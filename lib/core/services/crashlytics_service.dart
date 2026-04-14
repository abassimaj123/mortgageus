import 'package:flutter/foundation.dart';

// ── CrashlyticsService ────────────────────────────────────────────────────────
// Placeholder — wire Firebase Crashlytics once google-services.json is added.
//
// To activate:
//   1. Add firebase_crashlytics to pubspec.yaml
//   2. Initialize Firebase in main.dart (see firebase_options.dart)
//   3. Uncomment FirebaseCrashlytics lines below

class CrashlyticsService {
  CrashlyticsService._();
  static final CrashlyticsService instance = CrashlyticsService._();

  // final _crashlytics = FirebaseCrashlytics.instance; // uncomment after setup

  Future<void> init() async {
    if (kReleaseMode) {
      // await _crashlytics.setCrashlyticsCollectionEnabled(true);
      // FlutterError.onError = _crashlytics.recordFlutterFatalError;
      // PlatformDispatcher.instance.onError = (error, stack) {
      //   _crashlytics.recordError(error, stack, fatal: true);
      //   return true;
      // };
    }
  }

  Future<void> recordError(Object error, StackTrace? stack, {bool fatal = false}) async {
    if (kDebugMode) {
      debugPrint('[Crashlytics] ${fatal ? 'FATAL' : 'error'}: $error');
    }
    // await _crashlytics.recordError(error, stack, fatal: fatal);
  }

  Future<void> setUserId(String id) async {
    // await _crashlytics.setUserIdentifier(id);
  }

  Future<void> log(String message) async {
    // await _crashlytics.log(message);
  }
}

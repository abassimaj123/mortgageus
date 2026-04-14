import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  CrashlyticsService._();
  static final CrashlyticsService instance = CrashlyticsService._();

  Future<void> init() async {
    if (kReleaseMode) {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  }

  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false}) async {
    if (kDebugMode) {
      debugPrint('[Crashlytics] ${fatal ? 'FATAL' : 'error'}: $error');
      return;
    }
    await FirebaseCrashlytics.instance
        .recordError(error, stack, fatal: fatal);
  }
}

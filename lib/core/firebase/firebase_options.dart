// Generated from google-services.json (android-app-54282)
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('DefaultFirebaseOptions: unsupported platform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAVdM2OBORjb4fgCtWiqCwOJkkc5yhPRSY',
    appId: '1:385086392226:android:99865e8548d2a55fa6d4fb',
    messagingSenderId: '385086392226',
    projectId: 'android-app-54282',
    storageBucket: 'android-app-54282.firebasestorage.app',
  );
}

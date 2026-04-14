import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('DefaultFirebaseOptions: unsupported platform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAzAZMgasEkw6F5XAg1yqGR2oXTSOSySxI',
    appId:             '1:728953686695:android:63d8eaf493b025b9cae982',
    messagingSenderId: '728953686695',
    projectId:         'mortgageus-prod',
    storageBucket:     'mortgageus-prod.firebasestorage.app',
  );

  // iOS: add GoogleService-Info.plist and fill values after Mac build setup
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'REPLACE_WITH_IOS_API_KEY',
    appId:             'REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '728953686695',
    projectId:         'mortgageus-prod',
    storageBucket:     'mortgageus-prod.firebasestorage.app',
    iosBundleId:       'com.mortgageus.calculator',
  );
}

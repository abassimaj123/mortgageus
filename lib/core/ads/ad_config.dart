// ── AdMob Configuration ───────────────────────────────────────────────────────
// Production unit IDs are injected at build time via:
//   flutter build appbundle --release --dart-define-from-file=admob.json
// In debug — and in release when no prod ID is injected — Google official TEST
// IDs are used, so a build can NEVER ship a 'ca-app-pub-...XXXXXXXXXX' placeholder.
// The Android App ID is wired via android/local.properties (admob.app.id) →
// manifestPlaceholder ${admobAppId} → AndroidManifest.xml.
//
// Rules (enforced by AdService):
//   Banner        → permanent, Calculator screen bottom
//   Interstitial  → after every 5 calculations, min 5-min cooldown
//   Rewarded      → "Watch ad → 24h ad-free" bonus UX
//   NO App Open Ad

import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  // ⚠️ SCREENSHOT MODE — set to true for store captures, revert to false before release
  static const bool screenshotMode = false;

  static const bool adsEnabled = !screenshotMode; // set false to disable all ads globally

  // ── App IDs ───────────────────────────────────────────────────────────────
  // Android App ID is wired through android/local.properties → manifest, so the
  // value here is the Dart-side TEST reference only. iOS App ID → ios/Runner/Info.plist.
  static const String androidAppId =
      'ca-app-pub-3940256099942544~3347511713'; // TEST
  static const String iosAppId =
      'ca-app-pub-3940256099942544~1458002511'; // TEST

  // ── Google official TEST ad unit IDs (debug + release fallback) ───────────
  // Adaptive banner test unit — fixed 320x50 unit letterboxes when requested at an adaptive size.
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/9214589741';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testBannerIOS = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialIOS = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedIOS = 'ca-app-pub-3940256099942544/1712485313';

  // ── Production IDs injected via --dart-define-from-file=admob.json ─────────
  static const _prodBannerAndroid =
      String.fromEnvironment('ADMOB_BANNER_ANDROID');
  static const _prodInterstitialAndroid =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID');
  static const _prodRewardedAndroid =
      String.fromEnvironment('ADMOB_REWARDED_ANDROID');
  static const _prodBannerIOS = String.fromEnvironment('ADMOB_BANNER_IOS');
  static const _prodInterstitialIOS =
      String.fromEnvironment('ADMOB_INTERSTITIAL_IOS');
  static const _prodRewardedIOS = String.fromEnvironment('ADMOB_REWARDED_IOS');

  // ── Android Ad Unit IDs ───────────────────────────────────────────────────
  static String get bannerAndroid =>
      kReleaseMode && _prodBannerAndroid.isNotEmpty
          ? _prodBannerAndroid
          : _testBannerAndroid;
  static String get interstitialAndroid =>
      kReleaseMode && _prodInterstitialAndroid.isNotEmpty
          ? _prodInterstitialAndroid
          : _testInterstitialAndroid;
  static String get rewardedAndroid =>
      kReleaseMode && _prodRewardedAndroid.isNotEmpty
          ? _prodRewardedAndroid
          : _testRewardedAndroid;

  // ── iOS Ad Unit IDs ───────────────────────────────────────────────────────
  static String get banneriOS => kReleaseMode && _prodBannerIOS.isNotEmpty
      ? _prodBannerIOS
      : _testBannerIOS;
  static String get interstitialiOS =>
      kReleaseMode && _prodInterstitialIOS.isNotEmpty
          ? _prodInterstitialIOS
          : _testInterstitialIOS;
  static String get rewardediOS => kReleaseMode && _prodRewardedIOS.isNotEmpty
      ? _prodRewardedIOS
      : _testRewardedIOS;

  // ── Gate settings ─────────────────────────────────────────────────────────
  static const int calcThreshold =
      8; // interstitial every N actions — 5 was too aggressive, 8 reduces 1★ "too many ads"
  static const int cooldownMinutes = 5; // min between interstitials
  static const int timeThresholdSeconds =
      240; // interstitial after ~4 min of usage
  static const int rewardedDurationMinutes =
      60; // ad-free window after rewarded ad
  static const int rewardedMinSession =
      2; // show rewarded option only from session 2+
}

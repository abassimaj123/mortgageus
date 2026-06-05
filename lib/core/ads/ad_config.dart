// ── AdMob Configuration ───────────────────────────────────────────────────────
// BEFORE RELEASE: Replace all TEST IDs with real AdMob IDs from console.
// Real IDs format: ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN
//
// Rules (enforced by AdService):
//   Banner        → permanent, Calculator screen bottom
//   Interstitial  → after every 5 calculations, min 5-min cooldown
//   Rewarded      → "Watch ad → 24h ad-free" bonus UX
//   NO App Open Ad

class AdConfig {
  AdConfig._();

  // ⚠️ SCREENSHOT MODE — set to true for store captures, revert to false before release
  static const bool screenshotMode = false;

  static const bool adsEnabled = !screenshotMode; // set false to disable all ads globally

  // ── App IDs (replace with real IDs) ──────────────────────────────────────
  // TODO: android app ID from AdMob → android/app/src/main/AndroidManifest.xml
  // TODO: iOS app ID from AdMob     → ios/Runner/Info.plist
  static const String androidAppId =
      'ca-app-pub-3940256099942544~3347511713'; // TEST
  static const String iosAppId =
      'ca-app-pub-3940256099942544~1458002511'; // TEST

  // ── Android Ad Unit IDs ───────────────────────────────────────────────────
  // TODO: Create 3 ad units in AdMob for com.mortgageus.calculator (Android)
  static const String bannerAndroid =
      'ca-app-pub-3940256099942544/6300978111'; // TEST
  static const String interstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712'; // TEST
  static const String rewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917'; // TEST

  // ── iOS Ad Unit IDs ───────────────────────────────────────────────────────
  // TODO: Create 3 ad units in AdMob for com.mortgageus.calculator (iOS)
  static const String banneriOS =
      'ca-app-pub-3940256099942544/2934735716'; // TEST
  static const String interstitialiOS =
      'ca-app-pub-3940256099942544/4411468910'; // TEST
  static const String rewardediOS =
      'ca-app-pub-3940256099942544/1712485313'; // TEST

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

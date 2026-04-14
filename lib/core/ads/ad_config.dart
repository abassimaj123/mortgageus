// ── AdMob Configuration ───────────────────────────────────────────────────────
// BEFORE RELEASE: Replace all TEST IDs with real AdMob IDs from console.
// Real IDs format: ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN
//
// Rules (enforced by AdService):
//   Banner        → permanent, Calculator screen bottom
//   Interstitial  → after every 5 calculations, min 5-min cooldown
//   Rewarded      → "Unlock 60min Premium" + Share/History gate
//   NO App Open Ad

class AdConfig {
  AdConfig._();

  static const bool adsEnabled = true; // set false to disable all ads globally

  // ── App IDs (replace with real IDs) ──────────────────────────────────────
  // TODO: android app ID from AdMob → android/app/src/main/AndroidManifest.xml
  // TODO: iOS app ID from AdMob     → ios/Runner/Info.plist
  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713'; // TEST
  static const String iosAppId     = 'ca-app-pub-3940256099942544~1458002511'; // TEST

  // ── Android Ad Unit IDs ───────────────────────────────────────────────────
  // TODO: Create 3 ad units in AdMob for com.mortgageus.calculator (Android)
  static const String bannerAndroid       = 'ca-app-pub-3940256099942544/6300978111'; // TEST
  static const String interstitialAndroid = 'ca-app-pub-3940256099942544/1033173712'; // TEST
  static const String rewardedAndroid     = 'ca-app-pub-3940256099942544/5224354917'; // TEST

  // ── iOS Ad Unit IDs ───────────────────────────────────────────────────────
  // TODO: Create 3 ad units in AdMob for com.mortgageus.calculator (iOS)
  static const String banneriOS       = 'ca-app-pub-3940256099942544/2934735716'; // TEST
  static const String interstitialiOS = 'ca-app-pub-3940256099942544/4411468910'; // TEST
  static const String rewardediOS     = 'ca-app-pub-3940256099942544/1712485313'; // TEST

  // ── Gate settings ─────────────────────────────────────────────────────────
  static const int calcThreshold        = 5;            // interstitial every N calcs
  static const int cooldownMinutes      = 5;            // min between interstitials
  static const int rewardedDurationMins = 60;           // rewarded unlock duration
}

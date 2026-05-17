# MortgageUS — Play Store Release Checklist
Last updated: 2026-04-30

---

## ✅ DONE — Ready

- [x] 7 calculators — all logic validated, 167 unit tests passing
- [x] EN + ES localization complete
- [x] Dark mode support
- [x] Adaptive icon (Android 8+ round icon)
- [x] Android 12+ splash screen (ic_launcher, proper inset)
- [x] network_security_config.xml — HTTP blocked in production
- [x] android:allowBackup="false"
- [x] AdFreeService removed — single source of truth (FreemiumService)
- [x] debugUnlockPremium() guarded by kDebugMode
- [x] IAP completePurchase() called — Play Store compliant
- [x] IAP restore on init — Play Store compliant
- [x] Paywall dismissible — Play Store compliant
- [x] release AAB built with --obfuscate (48.2MB)
  → build/app/outputs/bundle/release/app-release.aab
  → debug symbols: build/debug_info/
- [x] Store listing EN written (store/en-US/listing.txt)
- [x] Store listing ES written (store/es-US/listing.txt)
- [x] Privacy policy written (store/privacy/index.html)

---

## 🔴 TODO BEFORE SUBMITTING AAB

### 1. Replace AdMob Test IDs
File: `lib/core/ads/ad_config.dart`
File: `android/app/src/main/AndroidManifest.xml`

Replace all 7 test IDs:
- androidAppId → real App ID from AdMob console
- bannerAndroid → real Banner unit ID
- interstitialAndroid → real Interstitial unit ID
- rewardedAndroid → real Rewarded unit ID
(iOS IDs can be added later if iOS release planned)

### 2. Create AdMob Account + Ad Units
- Go to admob.google.com
- Create app: "MortgageUS" → Android → package: com.mortgageus.calculator
- Create 3 ad units: Banner / Interstitial / Rewarded
- Copy IDs into ad_config.dart + AndroidManifest.xml
- Rebuild AAB after

### 3. Create IAP Product in Play Console
- Go to Play Console → MortgageUS → Monetize → In-app products
- Create product: ID = "premium_upgrade" (MUST match exactly)
- Type: One-time purchase (non-consumable)
- Price: $4.99 USD
- Title: "MortgageUS Premium"
- Description: "Unlimited saves, no ads, full history"
- Activate the product

### 4. Upload Privacy Policy
- Host store/privacy/index.html at:
  https://abassimaj.github.io/mortgageus-privacy/
  (create GitHub repo: abassimaj/mortgageus-privacy, enable Pages)
- OR use any hosting (Firebase Hosting, Netlify free tier)

### 5. Play Store Screenshots (6 required, 1080×1920 or 1080×2340)
Take screenshots of:
1. Calculator screen — result showing ($2,022/mo)
2. Amortization — donut chart + schedule visible
3. Affordability — both price estimates visible
4. Loan Comparator — 2-3 scenarios side by side
5. Extra Payments — savings chart
6. Refinance — break-even result

### 6. Play Console Setup
- Create app in Play Console (New app → Android → Free → Finance)
- Package: com.mortgageus.calculator
- Upload AAB: build/app/outputs/bundle/release/app-release.aab
- Upload debug symbols: build/debug_info/
- Fill store listing from store/en-US/listing.txt
- Add es-US listing from store/es-US/listing.txt
- Set privacy policy URL
- Complete content rating questionnaire (Finance → Everyone)
- Submit for review

---

## ⚠️ NOTES

- Keep build/debug_info/ safe — needed for deobfuscating crash reports in Crashlytics
- Test real AdMob IDs on a physical device before submitting
- IAP sandbox testing: use a test account in Play Console → License testing
- Review period: typically 3-7 days for new apps

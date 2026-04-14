# MortgageUS — Launch Checklist

All tasks that require your manual action before submitting to Google Play and App Store.

---

## 1. Generate Release Keystore (Android)

```bash
# Run this ONCE. Store the keystore and passwords safely — losing it = can't update the app.
keytool -genkey -v \
  -keystore D:/mob/MortgageUS/keystore/mortgageus-release.jks \
  -alias mortgageus \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=MortgageUS, OU=Mobile, O=YourCompany, L=YourCity, S=YourState, C=US"
```

Then create `android/key.properties` (already in `.gitignore`):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=mortgageus
storeFile=../keystore/mortgageus-release.jks
```

---

## 2. Create Firebase Project

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. Create project: **mortgageus**
3. Enable **Google Analytics** during setup
4. Register Android app: `com.mortgageus.calculator`
5. Register iOS app: `com.mortgageus.calculator`
6. Add `google-services.json` → `android/app/google-services.json`
7. Add `GoogleService-Info.plist` → `ios/Runner/GoogleService-Info.plist`
8. In `android/app/build.gradle.kts`, add plugin: `id("com.google.gms.google-services")`
9. In `android/build.gradle`, add classpath: `com.google.gms:google-services:4.4.1`
10. Run: `flutterfire configure` (installs FlutterFire CLI first if needed)
11. Uncomment Firebase lines in `lib/core/firebase/firebase_options.dart`
12. Add to `pubspec.yaml`:
    ```yaml
    firebase_core: ^3.x.x
    firebase_analytics: ^11.x.x
    firebase_crashlytics: ^4.x.x
    ```
13. Uncomment Firebase.initializeApp() in `lib/main.dart`

---

## 3. Create AdMob Ad Units

1. Go to [admob.google.com](https://admob.google.com)
2. Create app: **MortgageUS** (Android — `com.mortgageus.calculator`)
3. Create 3 ad units:
   - **Banner** → copy ID → `lib/core/ads/ad_config.dart` `bannerAndroid`
   - **Interstitial** → copy ID → `interstitialAndroid`
   - **Rewarded** → copy ID → `rewardedAndroid`
4. Copy the **Android App ID** → update `AndroidManifest.xml` `GADApplicationIdentifier`
5. Repeat for iOS app in AdMob:
   - Copy iOS App ID → `ios/Runner/Info.plist` `GADApplicationIdentifier`
   - Copy 3 iOS ad unit IDs → `ad_config.dart` iOS fields

---

## 4. Build Release Android

```bash
cd D:/mob/MortgageUS
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

---

## 5. Build Release iOS

Requirements: Mac with Xcode 15+, active Apple Developer account ($99/year).

```bash
flutter build ipa --release
# Output: build/ios/ipa/MortgageUS.ipa
```

Or open `ios/Runner.xcworkspace` in Xcode → Product → Archive → Distribute.

---

## 6. Host Privacy Policy

The privacy policy is required by both Google Play and App Store.

- File: `docs/privacy_policy.md`
- Host it at a public URL (options):
  - GitHub Pages: push to `gh-pages` branch → `https://abassimaj123.github.io/mortgageus/privacy`
  - Firebase Hosting: `firebase deploy --only hosting`
  - Any static host (Vercel, Netlify, etc.)
- You'll enter this URL in Play Console and App Store Connect

---

## 7. Play Store Assets

Prepare in `docs/store-assets/`:
- [x] `feature_graphic_1024x500.png` — generated ✓
- [ ] `icon_512x512.png` — resize master icon: `node scripts/generate_icons.js` already created it at `ios/.../Icon-App-1024x1024@1x.png` — crop/resize to 512×512
- [ ] 8 screenshots (see `docs/SCREENSHOTS_GUIDE.md`)
- [ ] Descriptions: see `docs/store-assets/play_store_descriptions.md`

---

## 8. App Store Assets

- [ ] 6 screenshots for iPhone 6.7" (1290×2796)
- [ ] 6 screenshots for iPhone 6.5" (1242×2688)  
- [ ] 6 screenshots for iPad 12.9" (2048×2732)
- [ ] App preview video (optional, 15-30 sec, strongly recommended)

---

## 9. Play Console Submission

1. Create app at [play.google.com/console](https://play.google.com/console)
2. App name: **MortgageUS — Mortgage Calculator**
3. Category: Finance
4. Upload AAB
5. Fill store listing (copy from `docs/store-assets/play_store_descriptions.md`)
6. Upload screenshots + feature graphic
7. Set privacy policy URL
8. Answer content rating questionnaire (Finance — General Audience)
9. Set price: Free
10. Submit for review (~3-7 days)

---

## 10. App Store Connect Submission

1. Create app at [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Bundle ID: `com.mortgageus.calculator`
3. Upload IPA via Xcode or Transporter
4. Fill metadata (copy from `docs/store-assets/play_store_descriptions.md`)
5. Upload screenshots
6. Set privacy policy URL
7. Submit for review (~1-3 days)

---

## Status

| Step | Status |
|------|--------|
| Keystore | ⏳ You must generate |
| Firebase project | ⏳ You must create |
| AdMob ad units | ⏳ You must create (6 units) |
| Privacy policy hosted | ⏳ You must host |
| Release AAB | ⏳ After keystore |
| Release IPA | ⏳ Needs Mac + Apple Dev account |
| Screenshots | ⏳ See SCREENSHOTS_GUIDE.md |
| Play Store listing | ⏳ Ready in play_store_descriptions.md |
| App Store listing | ⏳ Ready in play_store_descriptions.md |

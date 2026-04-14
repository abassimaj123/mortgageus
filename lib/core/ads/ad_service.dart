import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config.dart';

class AdService {
  InterstitialAd? _inter;
  RewardedAd?     _rewarded;

  int       _calcCount    = 0;
  DateTime? _lastInterTime;

  String get bannerId => Platform.isIOS ? AdConfig.banneriOS : AdConfig.bannerAndroid;

  Future<void> initialize() async {
    if (!AdConfig.adsEnabled) return;
    await MobileAds.instance.initialize();
    _loadInter();
    _loadRewarded();
  }

  void _loadInter() {
    final id = Platform.isIOS ? AdConfig.interstitialiOS : AdConfig.interstitialAndroid;
    InterstitialAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded:       (a) => _inter = a,
        onAdFailedToLoad: (_) => _inter = null,
      ),
    );
  }

  void _loadRewarded() {
    final id = Platform.isIOS ? AdConfig.rewardediOS : AdConfig.rewardedAndroid;
    RewardedAd.load(
      adUnitId: id,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded:       (a) => _rewarded = a,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  void onCalculation() {
    if (!AdConfig.adsEnabled) return;
    _calcCount++;
    if (_calcCount < AdConfig.calcThreshold) return;
    if (_lastInterTime != null) {
      final elapsed = DateTime.now().difference(_lastInterTime!).inMinutes;
      if (elapsed < AdConfig.cooldownMinutes) return;
    }
    if (_inter == null) return;
    _calcCount = 0;
    _lastInterTime = DateTime.now();
    _inter!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) { ad.dispose(); _inter = null; _loadInter(); },
      onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _inter = null; _loadInter(); },
    );
    _inter!.show();
  }

  bool get isRewardedReady => _rewarded != null;

  Future<bool> showRewarded() async {
    if (_rewarded == null) return false;
    bool earned = false;
    _rewarded!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent:    (ad) { ad.dispose(); _rewarded = null; _loadRewarded(); },
      onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _rewarded = null; _loadRewarded(); },
    );
    await _rewarded!.show(onUserEarnedReward: (ad, reward) => earned = true);
    return earned;
  }
}

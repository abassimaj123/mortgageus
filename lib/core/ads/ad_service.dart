import 'dart:async';
import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config.dart';
import '../freemium/freemium_service.dart';
import '../services/analytics_service.dart';

class AdService {
  static final instance = AdService._();
  AdService._();

  InterstitialAd? _inter;
  RewardedAd?     _rewarded;

  int       _actionCount   = 0;
  DateTime? _lastInterTime;
  DateTime? _sessionStart;

  static String get bannerId => Platform.isIOS ? AdConfig.banneriOS : AdConfig.bannerAndroid;

  Future<void> initialize() async {
    if (!AdConfig.adsEnabled) return;
    await MobileAds.instance.initialize();
    _sessionStart = DateTime.now();
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

  /// Call on every user action (calculation, tab switch, etc.)
  void onAction() {
    if (!AdConfig.adsEnabled) return;
    if (!freemiumService.showAds) return;
    _actionCount++;

    // Cooldown check
    if (_lastInterTime != null) {
      final elapsed = DateTime.now().difference(_lastInterTime!).inMinutes;
      if (elapsed < AdConfig.cooldownMinutes) return;
    }

    // Trigger: action count threshold OR time threshold
    final sessionSecs = _sessionStart != null
        ? DateTime.now().difference(_sessionStart!).inSeconds
        : 0;
    final byCount = _actionCount >= AdConfig.calcThreshold;
    final byTime  = sessionSecs >= AdConfig.timeThresholdSeconds;

    if (!byCount && !byTime) return;
    // Time-based trigger still requires at least 2 deliberate actions
    if (!byCount && byTime && _actionCount < 2) return;
    if (_inter == null) return;

    _actionCount   = 0;
    _sessionStart  = DateTime.now(); // reset time window
    _lastInterTime = DateTime.now();
    _inter!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) { ad.dispose(); _inter = null; _loadInter(); },
      onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _inter = null; _loadInter(); },
    );
    _inter!.show();
  }

  // Keep backward compat for existing callers
  void onCalculation() => onAction();

  bool get isRewardedReady => _rewarded != null;

  /// Shows the rewarded ad and returns true only after the user has fully
  /// watched it and earned the reward. Uses a Completer to await dismissal.
  Future<bool> showRewarded() async {
    if (_rewarded == null) return false;
    final completer = Completer<bool>();
    bool earned = false;

    _rewarded!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _rewarded = null;
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await _rewarded!.show(onUserEarnedReward: (_, __) {
      earned = true;
      AnalyticsService.instance.logRewardedAdWatched();
    });
    return completer.future;
  }
}

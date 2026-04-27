import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final freemiumService = FreemiumService._();

class FreemiumService {
  FreemiumService._();

  static const _keyPremium       = 'is_premium';
  static const _keyRewarded      = 'rewarded_until';
  static const _keyRewardedDay   = 'rewarded_day';
  static const _keyRewardedCount = 'rewarded_count';
  static const int freeHistoryLimit  = 5;
  static const int rewardedMinutes   = 60;
  static const int maxRewardedPerDay = 2;

  late SharedPreferences _prefs;

  final isPremiumNotifier  = ValueNotifier<bool>(false);
  final isRewardedNotifier = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = _prefs.getBool(_keyPremium) ?? false;
    _refreshRewarded();
    // Proactive expiry: revert isRewardedNotifier when 60-min window closes.
    Timer.periodic(const Duration(seconds: 30), (_) => _refreshRewarded());
  }

  void _refreshRewarded() {
    final s = _prefs.getString(_keyRewarded);
    isRewardedNotifier.value =
        s != null && DateTime.now().isBefore(DateTime.parse(s));
  }

  bool get isPremium  => isPremiumNotifier.value;
  bool get isRewarded { _refreshRewarded(); return isRewardedNotifier.value; }

  /// True when ads (banner + interstitial) should be displayed.
  bool get showAds => !isPremium && !isRewarded;

  /// Max number of history entries for free users.
  int get historyLimit => isPremium ? 999999 : freeHistoryLimit;

  int get rewardedMinutesLeft {
    _refreshRewarded();
    if (!isRewardedNotifier.value) return 0;
    final s = _prefs.getString(_keyRewarded)!;
    return DateTime.parse(s)
        .difference(DateTime.now())
        .inMinutes
        .clamp(0, rewardedMinutes);
  }

  /// True only when no active session AND daily limit not reached.
  bool canWatchRewarded() {
    if (isPremium) return false;
    if (isRewardedNotifier.value) return false; // no extending an active session
    return _todayCount() < maxRewardedPerDay;
  }

  int _todayKey() {
    final n = DateTime.now();
    return n.year * 10000 + n.month * 100 + n.day;
  }

  int _todayCount() {
    final savedDay = _prefs.getInt(_keyRewardedDay) ?? -1;
    if (savedDay != _todayKey()) return 0;
    return _prefs.getInt(_keyRewardedCount) ?? 0;
  }

  Future<void> activateRewarded() async {
    if (!canWatchRewarded()) return;
    final today = _todayKey();
    final count = _todayCount();
    await _prefs.setString(
      _keyRewarded,
      DateTime.now()
          .add(const Duration(minutes: rewardedMinutes))
          .toIso8601String(),
    );
    await _prefs.setInt(_keyRewardedDay, today);
    await _prefs.setInt(_keyRewardedCount, count + 1);
    isRewardedNotifier.value = true;
  }

  Future<void> activatePremium() async {
    isPremiumNotifier.value = true;
    await _prefs.setBool(_keyPremium, true);
  }

  /// DEV only — force premium without IAP (remove before release).
  void debugUnlockPremium() {
    if (kDebugMode) activatePremium();
  }
}

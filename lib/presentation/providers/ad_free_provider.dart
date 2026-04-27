import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ads/ad_service.dart';
import '../../core/services/ad_free_service.dart';
import '../../core/freemium/freemium_service.dart';

final adFreeProvider =
    StateNotifierProvider<AdFreeNotifier, bool>((ref) => AdFreeNotifier());

class AdFreeNotifier extends StateNotifier<bool> {
  Timer? _expiryTimer;

  AdFreeNotifier()
      : super(AdFreeService.instance.isActive || freemiumService.isRewarded) {
    // Keep shield in sync with any caller of freemiumService.activateRewarded()
    // (paywall_hard, ad_footer, etc.) — no Riverpod ref needed on their side.
    freemiumService.isRewardedNotifier.addListener(_syncFromFreemium);
    // Proactive expiry: revert shield automatically when 60-min window closes.
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void _syncFromFreemium() {
    if (freemiumService.isRewarded && !state) state = true;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    freemiumService.isRewardedNotifier.removeListener(_syncFromFreemium);
    super.dispose();
  }

  void refresh() =>
      state = AdFreeService.instance.isActive || freemiumService.isRewarded;

  /// Watch a rewarded ad → unlock 60 min ad-free.
  /// Returns true if the user earned the reward.
  Future<bool> unlockWithRewardedAd() async {
    final earned = await AdService.instance.showRewarded();
    if (earned) {
      // Sync both systems so banner + interstitials also stop
      await AdFreeService.instance.unlockForDuration(const Duration(minutes: 60));
      await freemiumService.activateRewarded(); // triggers _syncFromFreemium → state = true
    }
    return earned;
  }
}

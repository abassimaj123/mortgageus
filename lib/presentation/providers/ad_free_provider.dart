import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/freemium/freemium_service.dart';
import '../../main.dart' show adService;

final adFreeProvider =
    StateNotifierProvider<AdFreeNotifier, bool>((ref) => AdFreeNotifier());

class AdFreeNotifier extends StateNotifier<bool> {
  Timer? _expiryTimer;

  AdFreeNotifier()
      : super(freemiumService.isRewarded || freemiumService.hasFullAccess) {
    // Keep shield in sync with any caller of freemiumService.activateRewarded()
    // (paywall_hard, ad_footer, etc.) — no Riverpod ref needed on their side.
    freemiumService.isRewardedNotifier.addListener(_syncFromFreemium);
    freemiumService.isPremiumNotifier.addListener(_syncFromFreemium);
    // Proactive expiry: revert shield automatically when 60-min window closes.
    _expiryTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void _syncFromFreemium() {
    final active = freemiumService.isRewarded || freemiumService.hasFullAccess;
    if (active != state) state = active;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    freemiumService.isRewardedNotifier.removeListener(_syncFromFreemium);
    freemiumService.isPremiumNotifier.removeListener(_syncFromFreemium);
    super.dispose();
  }

  void refresh() =>
      state = freemiumService.isRewarded || freemiumService.hasFullAccess;

  /// Watch a rewarded ad → unlock 60 min ad-free.
  /// Returns true if the user earned the reward.
  Future<bool> unlockWithRewardedAd() async {
    final earned = await adService.showRewarded();
    if (earned) {
      await freemiumService
          .activateRewarded(); // triggers _syncFromFreemium → state = true
    }
    return earned;
  }
}

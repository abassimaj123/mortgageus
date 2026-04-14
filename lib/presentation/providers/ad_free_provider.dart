import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ads/ad_service.dart';
import '../../core/services/ad_free_service.dart';

final adFreeProvider =
    StateNotifierProvider<AdFreeNotifier, bool>((ref) => AdFreeNotifier());

class AdFreeNotifier extends StateNotifier<bool> {
  AdFreeNotifier() : super(AdFreeService.instance.isActive);

  void refresh() => state = AdFreeService.instance.isActive;

  /// Watch a rewarded ad → unlock 60 min ad-free.
  /// Returns true if the user earned the reward.
  Future<bool> unlockWithRewardedAd() async {
    final earned = await AdService.instance.showRewarded();
    if (earned) {
      await AdFreeService.instance.unlockForDuration(const Duration(minutes: 60));
      state = true;
    }
    return earned;
  }
}

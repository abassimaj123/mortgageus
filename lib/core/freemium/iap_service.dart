/// IAP service — re-exports CalcwiseIAP from library with app-specific configuration.
/// This file maintains backward compatibility while using the shared library implementation.
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:calcwise_core/calcwise_core.dart';
import '../services/analytics_service.dart';
import '../services/review_service.dart';
import 'freemium_service.dart';

// Re-export the iapErrorNotifier from library for backward compatibility
export 'package:calcwise_core/services/iap_service.dart' show iapErrorNotifier;

/// Global IAP singleton with ReviewService callback for MortgageUS.
class IAPService {
  IAPService._();
  static final instance = IAPService._();

  static const productId = 'premium_upgrade';

  CalcwiseIAP? _iap;
  final _fallbackPrice = ValueNotifier<String?>(null);

  /// Localized price notifier — exposed for UI to listen.
  ValueNotifier<String?> get localizedPrice =>
      _iap?.localizedPrice ?? _fallbackPrice;

  Future<void> initialize() async {
    _iap = CalcwiseIAP(
      productId: productId,
      freemium: freemiumService,
      analytics: AnalyticsService.instance,
      onPurchaseCompleted: () => ReviewService.instance.requestAfterPremium(),
    );
    await _iap!.initialize();
    PaywallHard.registerPrice(_iap!.localizedPrice);
  }

  Future<void> buy() async => _iap?.buy();

  Future<void> restore() async => _iap?.restore();

  void dispose() => _iap?.dispose();
}

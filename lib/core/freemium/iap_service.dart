import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'freemium_service.dart';
import '../services/analytics_service.dart';
import '../services/review_service.dart';

// Notifier so UI can react to IAP errors without needing a BuildContext in the service
final iapErrorNotifier = ValueNotifier<String?>(null);

class IAPService {
  IAPService._();
  static final instance = IAPService._();

  /// Must match the product ID created in Google Play Console.
  static const productId = 'premium_upgrade';

  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> initialize() async {
    _sub = InAppPurchase.instance.purchaseStream.listen(_handlePurchases);
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('IAP restore error: $e');
    }
  }

  /// Initiate the purchase flow. Call from a button tap.
  Future<void> buy() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      iapErrorNotifier.value = 'Store not available. Check your connection.';
      return;
    }
    final ProductDetailsResponse response;
    try {
      response = await InAppPurchase.instance
          .queryProductDetails({productId})
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      iapErrorNotifier.value = 'Request timed out. Try again.';
      return;
    } catch (e) {
      iapErrorNotifier.value = 'Could not reach the store. Try again.';
      debugPrint('IAP query error: $e');
      return;
    }
    if (response.productDetails.isEmpty) {
      iapErrorNotifier.value = 'Product not found. Try again later.';
      debugPrint('IAP product not found: $productId — check Play Console');
      return;
    }
    final param =
        PurchaseParam(productDetails: response.productDetails.first);
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
  }

  /// Restore a previous purchase (required for Google Play policy).
  Future<void> restore() async {
    try {
      await InAppPurchase.instance.restorePurchases();
      // Success signal — UI listens via purchaseStream/_handlePurchases
    } catch (e) {
      iapErrorNotifier.value = 'Restore failed. Try again later.';
      debugPrint('IAP restore error: $e');
    }
  }

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.productID == productId) {
        if (p.status == PurchaseStatus.purchased) {
          freemiumService.activatePremium();
          AnalyticsService.instance.logPurchaseCompleted();
          AnalyticsService.instance.setUserPremium(true);
          ReviewService.instance.requestAfterPremium();
          debugPrint('Premium activated');
        } else if (p.status == PurchaseStatus.restored) {
          freemiumService.activatePremium();
          AnalyticsService.instance.logPurchaseRestored();
          AnalyticsService.instance.setUserPremium(true);
          ReviewService.instance.requestAfterPremium();
          debugPrint('Premium restored');
        } else if (p.status == PurchaseStatus.error) {
          debugPrint('IAP error: ${p.error}');
          AnalyticsService.instance.logPurchaseFailed();
        }
        if (p.pendingCompletePurchase) {
          InAppPurchase.instance.completePurchase(p);
        }
      }
    }
  }

  void dispose() => _sub?.cancel();
}

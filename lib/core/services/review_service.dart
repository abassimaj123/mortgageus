import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests an in-app review at the right moment.
/// Triggers: after first save, after premium purchase.
/// Shown at most once per app version to avoid spamming.
class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  static const _keyShown = 'review_v2';

  Future<void> requestAfterSave() => _maybeRequest();
  Future<void> requestAfterPremium() => _maybeRequest();

  Future<void> _maybeRequest() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyShown) == true) return;

    final review = InAppReview.instance;
    if (!await review.isAvailable()) return;

    await prefs.setBool(_keyShown, true);
    await review.requestReview();
  }
}

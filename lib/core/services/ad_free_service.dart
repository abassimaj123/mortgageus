import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user is in a temporary ad-free window earned by
/// watching a rewarded ad. No paid tiers — the app is 100% free.
class AdFreeService {
  static final instance = AdFreeService._();
  AdFreeService._();

  static const _keyUntilMs = 'ad_free_until_ms';

  DateTime? _until;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyUntilMs);
    if (ms != null) _until = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get isActive {
    return _until != null && DateTime.now().isBefore(_until!);
  }

  /// Remaining duration, or null if not active.
  Duration? get remaining {
    if (_until == null) return null;
    final r = _until!.difference(DateTime.now());
    return r.isNegative ? null : r;
  }

  Future<void> unlockForDuration(Duration duration) async {
    _until = DateTime.now().add(duration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUntilMs, _until!.millisecondsSinceEpoch);
  }
}

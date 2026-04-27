import 'package:shared_preferences/shared_preferences.dart';
import 'freemium_service.dart';

// IMPORTANT: This file is intentionally kept identical across all apps.
// If you change trigger thresholds, update ALL copies:
//   MortgageCA · MortgageUS · AutoLoan · RentBuyUS
// Tuning a threshold? Change the named constant — not the logic.

final paywallService = PaywallService._();

class PaywallService {
  PaywallService._();

  static const _keySessionCount = 'paywall_session_count';

  // ── Trigger thresholds ────────────────────────────────────────────────────
  static const int _softSessionMin = 4; // first session that can show soft
  static const int _hardSessionMin = 7; // first session that can show hard
  static const int _softActionMin  = 5; // actions needed to trigger soft
  static const int _hardActionMin  = 4; // actions needed to trigger hard

  int  _sessionCount     = 0;
  int  _actionCount      = 0;   // actions in current session (resets each session)
  bool _shownThisSession = false; // show paywall at most once per session

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCount = prefs.getInt(_keySessionCount) ?? 0;
  }

  /// Call once per app launch — increments session counter, no paywall at open.
  Future<void> recordSession() async {
    if (freemiumService.isPremium) return;
    _sessionCount++;
    _actionCount      = 0;
    _shownThisSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySessionCount, _sessionCount);
  }

  /// Call on meaningful actions (tab switch, save, PDF export, feature visit).
  /// Never call on keystrokes or field changes.
  /// Returns which paywall to show (at most once per session).
  PaywallTrigger recordAction() {
    if (freemiumService.isPremium) return PaywallTrigger.none;
    if (_shownThisSession)        return PaywallTrigger.none;

    _actionCount++;

    // Sessions 1–3 : free exploration — no paywall
    if (_sessionCount < _softSessionMin) return PaywallTrigger.none;

    // Sessions 4–6 : gentle nudge after 5 meaningful actions
    if (_sessionCount < _hardSessionMin && _actionCount >= _softActionMin) {
      _shownThisSession = true;
      return PaywallTrigger.soft;
    }

    // Sessions 7+ : stronger nudge after 4 meaningful actions
    if (_sessionCount >= _hardSessionMin && _actionCount >= _hardActionMin) {
      _shownThisSession = true;
      return PaywallTrigger.hard;
    }

    return PaywallTrigger.none;
  }

  /// Rewarded option visible only from session 2+
  bool get shouldShowRewarded => _sessionCount >= 2;

  int get sessionCount => _sessionCount;
}

enum PaywallTrigger { none, soft, hard }

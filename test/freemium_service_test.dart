import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:mortgage_us/core/freemium/freemium_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FreemiumService — daily rewarded cap unit tests
//
// CalcwiseFreemium uses appKey-namespaced SharedPreferences keys:
//   appKey = 'mortgageus'
//   mortgageus_premium      → isPremium
//   mortgageus_rewarded_exp → rewarded expiry ISO string
//   mortgageus_rewarded_day → today key (yyyyMMdd int)
//   mortgageus_rewarded_count → count of rewarded views today
//   mortgageus_calc_count   → calculation count gate
//
// Key behaviours tested:
//   - canWatchRewarded() gates on premium, active session, and daily limit
//   - Daily count resets when the stored day differs from today
//   - activateRewarded() persists count + date and flips isRewardedNotifier
//   - maxRewardedPerDay = 2 (strategic: 2×60min/day)
// ─────────────────────────────────────────────────────────────────────────────

// Namespaced keys matching appKey = 'mortgageus'
const _kPremium  = 'mortgageus_premium';
const _kExp      = 'mortgageus_rewarded_exp';
const _kDay      = 'mortgageus_rewarded_day';
const _kCount    = 'mortgageus_rewarded_count';

int _todayKey() {
  final n = DateTime.now();
  return n.year * 10000 + n.month * 100 + n.day;
}

int _yesterdayKey() {
  final n = DateTime.now().subtract(const Duration(days: 1));
  return n.year * 10000 + n.month * 100 + n.day;
}

void main() {
  // Re-initialise the singleton before every test with a clean prefs state.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await freemiumService.initialize();
  });

  group('FreemiumService.canWatchRewarded()', () {
    test('returns true for a fresh user', () {
      expect(freemiumService.canWatchRewarded(), isTrue);
    });

    test('returns false when user is premium', () async {
      SharedPreferences.setMockInitialValues({_kPremium: true});
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isFalse);
    });

    test('returns false when daily cap reached', () async {
      SharedPreferences.setMockInitialValues({
        _kDay:   _todayKey(),
        _kCount: MonetizationConfig.maxRewardedPerDay,
      });
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isFalse);
    });

    test('returns true when cap was reached yesterday (daily reset)', () async {
      SharedPreferences.setMockInitialValues({
        _kDay:   _yesterdayKey(),
        _kCount: MonetizationConfig.maxRewardedPerDay,
      });
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isTrue);
    });

    test('returns false during an active rewarded session', () async {
      // Simulate an active session: expiry is far in the future.
      final future = DateTime.now().add(const Duration(minutes: 59));
      SharedPreferences.setMockInitialValues({
        _kExp:   future.toIso8601String(),
        _kDay:   _todayKey(),
        _kCount: 1,
      });
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isFalse);
    });

    test('returns true when session expired even though count < cap', () async {
      // Expired session — isRewardedNotifier should be false.
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues({
        _kExp:   past.toIso8601String(),
        _kDay:   _todayKey(),
        _kCount: 1,
      });
      await freemiumService.initialize();
      expect(freemiumService.isRewardedNotifier.value, isFalse);
      expect(freemiumService.canWatchRewarded(), isTrue);
    });
  });

  group('FreemiumService.activateRewarded()', () {
    test('increments rewarded_count in prefs', () async {
      await freemiumService.activateRewarded();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_kCount), 1);
    });

    test('sets isRewardedNotifier to true', () async {
      await freemiumService.activateRewarded();
      expect(freemiumService.isRewardedNotifier.value, isTrue);
    });

    test('does not activate when cap is already reached', () async {
      SharedPreferences.setMockInitialValues({
        _kDay:   _todayKey(),
        _kCount: MonetizationConfig.maxRewardedPerDay,
      });
      await freemiumService.initialize();
      await freemiumService.activateRewarded(); // should be blocked
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_kCount), MonetizationConfig.maxRewardedPerDay);
    });

    test('second activation brings count to 2 and still allows watching', () async {
      await freemiumService.activateRewarded();

      // Simulate session expiry so canWatchRewarded() allows a second view.
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kExp, past.toIso8601String());
      await freemiumService.initialize(); // re-read prefs

      expect(freemiumService.canWatchRewarded(), isTrue);
      await freemiumService.activateRewarded();
      final prefs2 = await SharedPreferences.getInstance();
      expect(prefs2.getInt(_kCount), 2);
    });

    test('third activation is blocked (cap = 2)', () async {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final prefs = await SharedPreferences.getInstance();

      // Two successful activations.
      await freemiumService.activateRewarded();
      await prefs.setString(_kExp, past.toIso8601String());
      await freemiumService.initialize();

      await freemiumService.activateRewarded();

      // Now at cap (2) — third call must be ignored.
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.setString(_kExp, past.toIso8601String());
      await freemiumService.initialize();

      expect(freemiumService.canWatchRewarded(), isFalse);
      await freemiumService.activateRewarded();
      final prefs3 = await SharedPreferences.getInstance();
      expect(prefs3.getInt(_kCount), 2); // still 2 — cap enforced
    });
  });

  group('FreemiumService constants', () {
    test('maxRewardedPerDay is 2', () {
      expect(MonetizationConfig.maxRewardedPerDay, 2);
    });

    test('rewardedDurationMinutes is 60', () {
      expect(MonetizationConfig.rewardedDurationMinutes, 60);
    });

    test('freeHistoryLimit is 5', () {
      expect(MonetizationConfig.freeHistoryLimit, 5);
    });
  });
}

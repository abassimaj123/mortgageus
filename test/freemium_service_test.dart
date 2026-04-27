import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mortgage_us/core/freemium/freemium_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FreemiumService — daily rewarded cap unit tests
//
// Key behaviour under test:
//   - canWatchRewarded() gates on premium, active session, and daily limit
//   - _todayCount() resets when the stored day differs from today
//   - activateRewarded() persists count + date and flips isRewardedNotifier
// ─────────────────────────────────────────────────────────────────────────────

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
      SharedPreferences.setMockInitialValues({'is_premium': true});
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isFalse);
    });

    test('returns false when daily cap reached', () async {
      SharedPreferences.setMockInitialValues({
        'rewarded_day':   _todayKey(),
        'rewarded_count': FreemiumService.maxRewardedPerDay,
      });
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isFalse);
    });

    test('returns true when cap was reached yesterday (daily reset)', () async {
      SharedPreferences.setMockInitialValues({
        'rewarded_day':   _yesterdayKey(),
        'rewarded_count': FreemiumService.maxRewardedPerDay,
      });
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isTrue);
    });

    test('returns false during an active rewarded session', () async {
      // Simulate an active session: expiry is far in the future.
      final future = DateTime.now().add(const Duration(minutes: 59));
      SharedPreferences.setMockInitialValues({
        'rewarded_until': future.toIso8601String(),
        'rewarded_day':   _todayKey(),
        'rewarded_count': 1,
      });
      await freemiumService.initialize();
      expect(freemiumService.canWatchRewarded(), isFalse);
    });

    test('returns true when session expired even though count < cap', () async {
      // Expired session — isRewardedNotifier should be false.
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues({
        'rewarded_until': past.toIso8601String(),
        'rewarded_day':   _todayKey(),
        'rewarded_count': 1,
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
      expect(prefs.getInt('rewarded_count'), 1);
    });

    test('sets isRewardedNotifier to true', () async {
      await freemiumService.activateRewarded();
      expect(freemiumService.isRewardedNotifier.value, isTrue);
    });

    test('does not activate when cap is already reached', () async {
      SharedPreferences.setMockInitialValues({
        'rewarded_day':   _todayKey(),
        'rewarded_count': FreemiumService.maxRewardedPerDay,
      });
      await freemiumService.initialize();
      await freemiumService.activateRewarded(); // should be blocked
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rewarded_count'), FreemiumService.maxRewardedPerDay);
    });

    test('second activation brings count to 2 and still allows watching', () async {
      await freemiumService.activateRewarded();

      // Simulate session expiry so canWatchRewarded() allows a second view.
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rewarded_until', past.toIso8601String());
      await freemiumService.initialize(); // re-read prefs

      expect(freemiumService.canWatchRewarded(), isTrue);
      await freemiumService.activateRewarded();
      final prefs2 = await SharedPreferences.getInstance();
      expect(prefs2.getInt('rewarded_count'), 2);
    });

    test('third activation is blocked (cap = 2)', () async {
      // Two successful activations.
      await freemiumService.activateRewarded();

      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rewarded_until', past.toIso8601String());
      await freemiumService.initialize();

      await freemiumService.activateRewarded();

      // Now at cap — third call must be ignored.
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.setString('rewarded_until', past.toIso8601String());
      await freemiumService.initialize();

      expect(freemiumService.canWatchRewarded(), isFalse);
      await freemiumService.activateRewarded();
      final prefs3 = await SharedPreferences.getInstance();
      expect(prefs3.getInt('rewarded_count'), 2); // still 2
    });
  });

  group('FreemiumService constants', () {
    test('maxRewardedPerDay is 2', () {
      expect(FreemiumService.maxRewardedPerDay, 2);
    });

    test('rewardedMinutes is 60', () {
      expect(FreemiumService.rewardedMinutes, 60);
    });

    test('freeHistoryLimit is 5', () {
      expect(FreemiumService.freeHistoryLimit, 5);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart';

// ── In-memory adapter ─────────────────────────────────────────────────────────

class _MemoryAdapter implements DatabaseAdapter {
  final List<Map<String, dynamic>> _rows = [];
  int _nextId = 1;

  int get rowCount => _rows.length;

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final id = _nextId++;
    _rows.add({...row, 'id': id});
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    var result = _rows.where((r) {
      if (r['app_key'] != appKey) return false;
      if (screenId != null && r['screen_id'] != screenId) return false;
      if (isPinned != null) {
        final pinVal = (r['is_pinned'] as int) == 1;
        if (pinVal != isPinned) return false;
      }
      return true;
    }).toList();
    result.sort((a, b) {
      final aPin = a['is_pinned'] as int;
      final bPin = b['is_pinned'] as int;
      if (aPin != bPin) return bPin.compareTo(aPin);
      return (b['saved_at'] as int).compareTo(a['saved_at'] as int);
    });
    if (limit != null && result.length > limit) result = result.sublist(0, limit);
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({
    required String appKey,
    required String resultHash,
  }) async {
    try {
      return _rows.firstWhere(
        (r) => r['app_key'] == appKey && r['result_hash'] == resultHash,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    final idx = _rows.indexWhere((r) => r['id'] == id);
    if (idx < 0) return 0;
    _rows[idx] = {..._rows[idx], ...values};
    return 1;
  }

  @override
  Future<int> deleteRow(int id) async {
    final before = _rows.length;
    _rows.removeWhere((r) => r['id'] == id);
    return before - _rows.length;
  }

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async {
    return _rows.where((r) {
      if (r['app_key'] != appKey) return false;
      if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
      return true;
    }).length;
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({
    required String appKey,
    required int limit,
  }) async {
    final rows = _rows
        .where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 0)
        .toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({
    required String appKey,
    required int limit,
  }) async {
    final rows = _rows
        .where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 1)
        .toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MemoryAdapter adapter;
  late CalcwiseFreemium freemium;
  late SmartHistoryService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = _MemoryAdapter();
    freemium = CalcwiseFreemium(appKey: 'mortgageus');
    await freemium.initialize();
    svc = SmartHistoryService(
      db: adapter,
      freemium: freemium,
      overrideSaveDebounce: Duration.zero,
    );
  });

  tearDown(() => svc.dispose());

  group('MortgageUS — save → history scenarios', () {
    test('scenario: calculate mortgage → entry appears in history', () async {
      // GIVEN: typical US mortgage (mirrors _l1Payload / _l2Payload in calculator_screen.dart)
      const homePrice = 450000.0;
      const downPct = 20.0;
      const rate = 6.75;
      const termYears = 30;
      const monthlyPayment = 2337.0;

      final inputHash = ResultHasher.hashMixed({
        'home_price': ResultHasher.roundTo(homePrice, 1000),
        'down_pct': ResultHasher.roundTo(downPct, 5),
        'rate': ResultHasher.roundTo(rate, 0.125),
        'term': termYears.toDouble(),
      });

      // WHEN: auto-save triggered (mirrors _scheduleAutoSave in calculator_screen.dart)
      var savedCalled = false;
      svc.scheduleAutoSave(
        appKey: 'mortgageus',
        screenId: 'mortgage_calculator',
        inputHash: inputHash,
        l1: {
          'home_price': homePrice,
          'down_payment': homePrice * downPct / 100,
          'rate': rate,
          'term': termYears,
          'monthly_payment': monthlyPayment,
          'total_interest': 480000.0,
        },
        l2: {
          'inputs': {
            'home_price': homePrice,
            'down_percent': downPct,
            'annual_rate': rate,
            'term_years': termYears,
            'loan_type': 'Fixed',
          },
          'results': {
            'monthly_payment': monthlyPayment,
            'total_interest': 480000.0,
            'loan_amount': homePrice * (1 - downPct / 100),
          },
        },
        onSaved: () => savedCalled = true,
      );
      await _pump();

      // THEN: entry visible in history
      final history = await svc.getHistory('mortgageus');
      expect(history, isNotEmpty,
          reason: 'History must contain the saved entry');
      expect(history.first.l1['home_price'], homePrice);
      expect(savedCalled, isTrue,
          reason: 'onSaved must fire — anti-regression for HistoryScreen race condition');
    });

    test('scenario: two different mortgages → both entries in history', () async {
      for (var i = 0; i < 2; i++) {
        final price = 300000.0 + i * 150000;
        svc.scheduleAutoSave(
          appKey: 'mortgageus',
          screenId: 'mortgage_calculator',
          inputHash: 'hash-us-$i',
          l1: {'home_price': price, 'rate': 6.75, 'monthly_payment': 1500.0 + i * 500},
          l2: {
            'inputs': {'home_price': price, 'annual_rate': 6.75, 'term_years': 30},
            'results': {'monthly_payment': 1500.0 + i * 500},
          },
        );
        await _pump();
      }
      final history = await svc.getHistory('mortgageus');
      expect(history.length, 2);
    });

    test('scenario: same inputs twice → only one history entry (no duplicates)', () async {
      const hash = 'same-hash-mortgageus';
      for (var i = 0; i < 3; i++) {
        svc.scheduleAutoSave(
          appKey: 'mortgageus',
          screenId: 'mortgage_calculator',
          inputHash: hash,
          l1: {'home_price': 400000.0, 'rate': 6.5},
          l2: {
            'inputs': {'home_price': 400000.0, 'annual_rate': 6.5},
            'results': {'monthly_payment': 2150.0},
          },
        );
        await _pump();
      }
      expect(adapter.rowCount, 1,
          reason: 'Identical inputs must not create duplicates');
    });

    test('scenario: pinned mortgage survives ring buffer eviction', () async {
      await svc.saveScenario(
        appKey: 'mortgageus',
        screenId: 'mortgage_calculator',
        inputHash: 'pinned-us-scenario',
        l1: {'home_price': 750000.0, 'rate': 5.99, 'monthly_payment': 3500.0},
        l2: {
          'inputs': {'home_price': 750000.0, 'annual_rate': 5.99},
          'results': {'monthly_payment': 3500.0},
        },
        label: 'Dream home',
      );
      for (var i = 0; i < MonetizationConfig.freeRingBufferSize + 2; i++) {
        svc.scheduleAutoSave(
          appKey: 'mortgageus',
          screenId: 'mortgage_calculator',
          inputHash: 'auto-us-$i',
          l1: {'home_price': i * 10000.0, 'rate': 7.0},
          l2: {
            'inputs': {'home_price': i * 10000.0},
            'results': {'monthly_payment': i * 50.0},
          },
        );
        await _pump();
      }
      final pinned = await svc.getPinned('mortgageus');
      expect(pinned, isNotEmpty,
          reason: 'Pinned scenario must survive ring buffer eviction');
      expect(pinned.first.l1['home_price'], 750000.0);
    });
  });
}

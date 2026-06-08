import 'dart:convert';

import 'package:calcwise_core/calcwise_core.dart' show DatabaseAdapter;
import 'database_helper.dart';

/// DatabaseAdapter implementation for MortgageUS.
///
/// Bridges SmartHistoryService (which speaks HistoryEntry / l1_json / l2_json)
/// to MortgageUS's flat sqflite `mortgage_us` table.
///
/// `app_key` / `screen_id` are always 'mortgageus' / 'calculator' for this app.
/// Only the MAIN calculator's single-result auto-save / scenarios are routed
/// through SmartHistory — comparison pairs (comparison_id) are left untouched.
class MortgageUSDatabaseAdapter implements DatabaseAdapter {
  static const _appKey = 'mortgageus';
  static const _screenId = 'calculator';

  // ── Insert ──────────────────────────────────────────────────────────────────

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final l2 = jsonDecode(row['l2_json'] as String) as Map<String, dynamic>;
    // Support both nested {inputs:{...}, results:{...}} and legacy flat structure.
    final inputs = (l2['inputs'] as Map<String, dynamic>?) ?? l2;
    final results = (l2['results'] as Map<String, dynamic>?) ?? l2;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(row['saved_at'] as int);

    return DatabaseHelper.instance.insertHistory({
      'home_price': (inputs['home_price'] as num?)?.toDouble() ?? 0.0,
      'down_percent': (inputs['down_percent'] as num?)?.toDouble() ?? 0.0,
      'annual_rate': (inputs['annual_rate'] as num?)?.toDouble() ?? 0.0,
      'monthly_payment': (results['monthly_payment'] as num?)?.toDouble() ?? 0.0,
      'total_interest': (results['total_interest'] as num?)?.toDouble() ?? 0.0,
      'loan_amount': (results['loan_amount'] as num?)?.toDouble() ?? 0.0,
      'loan_type': (inputs['loan_type'] as String?) ?? 'Conventional',
      'term_years': (inputs['term_years'] as num?)?.toInt() ?? 30,
      'tax_rate': (inputs['tax_rate'] as num?)?.toDouble() ?? 1.1,
      'insurance': (inputs['insurance'] as num?)?.toDouble() ?? 1750.0,
      'hoa': (inputs['hoa'] as num?)?.toDouble() ?? 0.0,
      'label': inputs['label'],
      'created_at': savedAt.toIso8601String(),
      'input_hash': row['result_hash'],
      'is_pinned': row['is_pinned'] ?? 0,
      'pin_label': row['pin_label'],
      'pin_order': row['pin_order'] ?? 0,
      'l1_json': row['l1_json'],
    });
  }

  // ── Query ────────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    final db = await DatabaseHelper.instance.database;
    String? where;
    List<dynamic>? whereArgs;
    if (isPinned != null) {
      where = 'is_pinned = ?';
      whereArgs = [isPinned ? 1 : 0];
    }
    final rows = await db.query(
      'mortgage_us',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'is_pinned DESC, pin_order DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({
    required String appKey,
    required String resultHash,
  }) async {
    final row = await DatabaseHelper.instance.getHistoryByHash(resultHash);
    return row == null ? null : _toAdapterRow(row);
  }

  // ── Update / Delete ──────────────────────────────────────────────────────────

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    return DatabaseHelper.instance.updateHistoryEntry(id, values);
  }

  @override
  Future<int> deleteRow(int id) async {
    await DatabaseHelper.instance.deleteHistory(id);
    return 1;
  }

  // ── Count / Eviction ─────────────────────────────────────────────────────────

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async {
    return DatabaseHelper.instance.countHistory(isPinned: isPinned);
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({
    required String appKey,
    required int limit,
  }) async {
    final rows = await DatabaseHelper.instance.getOldestAutoSaves(limit);
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({
    required String appKey,
    required int limit,
  }) async {
    final rows = await DatabaseHelper.instance.getOldestPinnedEntries(limit);
    return rows.map(_toAdapterRow).toList();
  }

  // ── Mapping ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toAdapterRow(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '')
            ?.millisecondsSinceEpoch ??
        0;
    final l1Json = (row['l1_json'] as String?) ?? _buildDefaultL1Json(row);
    final l2Json = _buildL2Json(row);
    return {
      'id': row['id'],
      'app_key': _appKey,
      'screen_id': _screenId,
      'result_hash': (row['input_hash'] as String?) ?? '',
      'l1_json': l1Json,
      'l2_json': l2Json,
      'saved_at': createdAt,
      'is_pinned': (row['is_pinned'] as int?) ?? 0,
      'pin_label': row['pin_label'],
      'pin_order': (row['pin_order'] as int?) ?? 0,
    };
  }

  String _buildDefaultL1Json(Map<String, dynamic> row) {
    return jsonEncode({
      'label': row['label'],
      'monthly_payment': (row['monthly_payment'] as num?)?.toDouble() ?? 0.0,
      'home_price': (row['home_price'] as num?)?.toDouble() ?? 0.0,
    });
  }

  String _buildL2Json(Map<String, dynamic> row) {
    return jsonEncode({
      'home_price': row['home_price'],
      'down_percent': row['down_percent'],
      'annual_rate': row['annual_rate'],
      'monthly_payment': row['monthly_payment'],
      'total_interest': row['total_interest'],
      'loan_amount': row['loan_amount'],
      'loan_type': row['loan_type'],
      'term_years': row['term_years'],
      'tax_rate': row['tax_rate'],
      'insurance': row['insurance'],
      'hoa': row['hoa'],
      'label': row['label'],
    });
  }
}

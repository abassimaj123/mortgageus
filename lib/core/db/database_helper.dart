import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final p = join(await getDatabasesPath(), 'mortgage_us.db');
    return openDatabase(p,
        version: 5, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE mortgage_us (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        home_price REAL NOT NULL,
        down_percent REAL NOT NULL,
        annual_rate REAL NOT NULL,
        monthly_payment REAL NOT NULL,
        total_interest REAL NOT NULL,
        loan_amount REAL NOT NULL,
        loan_type TEXT NOT NULL,
        term_years INTEGER NOT NULL DEFAULT 30,
        tax_rate REAL NOT NULL DEFAULT 1.1,
        insurance REAL NOT NULL DEFAULT 1750,
        hoa REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        comparison_id TEXT,
        label TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        input_hash TEXT,
        pin_label TEXT,
        pin_order INTEGER NOT NULL DEFAULT 0,
        l1_json TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE mortgage_us ADD COLUMN term_years INTEGER NOT NULL DEFAULT 30');
      await db.execute(
          'ALTER TABLE mortgage_us ADD COLUMN tax_rate REAL NOT NULL DEFAULT 1.1');
      await db.execute(
          'ALTER TABLE mortgage_us ADD COLUMN insurance REAL NOT NULL DEFAULT 1750');
      await db.execute(
          'ALTER TABLE mortgage_us ADD COLUMN hoa REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE mortgage_us ADD COLUMN comparison_id TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE mortgage_us ADD COLUMN label TEXT');
    }
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE mortgage_us ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE mortgage_us ADD COLUMN input_hash TEXT');
      await db.execute('ALTER TABLE mortgage_us ADD COLUMN pin_label TEXT');
      await db.execute(
          'ALTER TABLE mortgage_us ADD COLUMN pin_order INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE mortgage_us ADD COLUMN l1_json TEXT');
    }
  }

  Future<int> insertHistory(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('mortgage_us', row);
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await database;
    return db.query('mortgage_us',
        orderBy: 'is_pinned DESC, pin_order DESC, created_at DESC');
  }

  Future<Map<String, dynamic>?> getHistoryByHash(String hash) async {
    final db = await database;
    final rows = await db.query('mortgage_us',
        where: 'input_hash = ?', whereArgs: [hash], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> updateHistoryEntry(int id, Map<String, dynamic> values) async {
    final db = await database;
    return db.update('mortgage_us', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countHistory({bool? isPinned}) async {
    final db = await database;
    final String sql;
    if (isPinned == null) {
      sql = 'SELECT COUNT(*) FROM mortgage_us';
    } else {
      sql =
          'SELECT COUNT(*) FROM mortgage_us WHERE is_pinned = ${isPinned ? 1 : 0}';
    }
    final result = await db.rawQuery(sql);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getOldestAutoSaves(int limit) async {
    final db = await database;
    return db.query('mortgage_us',
        where: 'is_pinned = 0', orderBy: 'created_at ASC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getOldestPinnedEntries(int limit) async {
    final db = await database;
    return db.query('mortgage_us',
        where: 'is_pinned = 1',
        orderBy: 'pin_order ASC, created_at ASC',
        limit: limit);
  }

  Future<void> deleteHistory(int id) async {
    final db = await database;
    await db.delete('mortgage_us', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('mortgage_us');
  }

  /// Deletes the oldest non-pinned entry (or the full comparison pair if it has
  /// a comparison_id). Used for free-user FIFO cap. Pinned scenarios are never
  /// evicted by this method.
  Future<void> deleteOldestHistory() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT id, comparison_id FROM mortgage_us WHERE is_pinned = 0 ORDER BY created_at ASC, id ASC LIMIT 1',
    );
    if (rows.isEmpty) return;
    final cid = rows.first['comparison_id'] as String?;
    if (cid != null && cid.isNotEmpty) {
      await db
          .delete('mortgage_us', where: 'comparison_id = ?', whereArgs: [cid]);
    } else {
      await db.delete('mortgage_us',
          where: 'id = ?', whereArgs: [rows.first['id']]);
    }
  }

  /// Deletes all entries that share the given comparison_id.
  Future<void> deleteByComparisonId(String comparisonId) async {
    final db = await database;
    await db.delete('mortgage_us',
        where: 'comparison_id = ?', whereArgs: [comparisonId]);
  }
}

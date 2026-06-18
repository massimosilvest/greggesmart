import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'greggesmart.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _creaTabelle(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS master');
        await db.execute('DROP TABLE IF EXISTS storico');
        await db.execute('DROP TABLE IF EXISTS pecore');
        await db.execute('DROP TABLE IF EXISTS configurazione');
        await _creaTabelle(db);
      },
    );
  }

  Future<void> _creaTabelle(Database db) async {
    await db.execute('''
      CREATE TABLE pecore (
        tag_id INTEGER PRIMARY KEY,
        nome TEXT NOT NULL,
        rfid TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE storico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tag_id INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        boot_count INTEGER NOT NULL,
        battery_pct INTEGER NOT NULL,
        battery_mv INTEGER NOT NULL,
        temperature INTEGER NOT NULL,
        rssi INTEGER NOT NULL,
        FOREIGN KEY (tag_id) REFERENCES pecore (tag_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE master (
        tag_id INTEGER PRIMARY KEY,
        nome TEXT,
        rfid TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE configurazione (
        chiave TEXT PRIMARY KEY,
        valore TEXT NOT NULL
      )
    ''');
  }

  // ── PECORE ──────────────────────────────────────────

  Future<void> salvaPecora({
    required int tagId,
    required String nome,
    String? rfid,
    String? note,
  }) async {
    final db = await database;
    await db.insert('pecore', {
      'tag_id': tagId,
      'nome': nome,
      'rfid': rfid,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPecore() async {
    final db = await database;
    return await db.query('pecore', orderBy: 'nome ASC');
  }

  Future<Map<String, dynamic>?> getPecora(int tagId) async {
    final db = await database;
    final result = await db.query(
      'pecore',
      where: 'tag_id = ?',
      whereArgs: [tagId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> eliminaPecora(int tagId) async {
    final db = await database;
    await db.delete('pecore', where: 'tag_id = ?', whereArgs: [tagId]);
    await db.delete('storico', where: 'tag_id = ?', whereArgs: [tagId]);
  }

  // ── STORICO ─────────────────────────────────────────

  Future<void> salvaTrasmissione({
    required int tagId,
    required int bootCount,
    required int batteryPct,
    required int batteryMv,
    required int temperature,
    required int rssi,
  }) async {
    final db = await database;
    await db.insert('storico', {
      'tag_id': tagId,
      'timestamp': DateTime.now().toIso8601String(),
      'boot_count': bootCount,
      'battery_pct': batteryPct,
      'battery_mv': batteryMv,
      'temperature': temperature,
      'rssi': rssi,
    });
  }

  Future<List<Map<String, dynamic>>> getStorico(
    int tagId, {
    int giorni = 7,
  }) async {
    final db = await database;
    final from = DateTime.now()
        .subtract(Duration(days: giorni))
        .toIso8601String();
    return await db.query(
      'storico',
      where: 'tag_id = ? AND timestamp > ?',
      whereArgs: [tagId, from],
      orderBy: 'timestamp DESC',
    );
  }

  Future<void> pulisciStorico() async {
    final db = await database;
    final limit = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    await db.delete('storico', where: 'timestamp < ?', whereArgs: [limit]);
  }

  // ── MASTER ──────────────────────────────────────────

  Future<void> salvaMaster({
    required int tagId,
    String? nome,
    String? rfid,
    String? note,
  }) async {
    final db = await database;
    await db.insert('master', {
      'tag_id': tagId,
      'nome': nome,
      'rfid': rfid,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getMaster() async {
    final db = await database;
    return await db.query('master', orderBy: 'created_at ASC');
  }

  Future<Map<String, dynamic>?> getSingoloMaster(int tagId) async {
    final db = await database;
    final result = await db.query(
      'master',
      where: 'tag_id = ?',
      whereArgs: [tagId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> eliminaMaster(int tagId) async {
    final db = await database;
    await db.delete('master', where: 'tag_id = ?', whereArgs: [tagId]);
  }

  // ── CONFIGURAZIONE ──────────────────────────────────

  Future<void> salvaConfigurazione(String chiave, String valore) async {
    final db = await database;
    await db.insert('configurazione', {
      'chiave': chiave,
      'valore': valore,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getConfigurazione(String chiave) async {
    final db = await database;
    final result = await db.query(
      'configurazione',
      where: 'chiave = ?',
      whereArgs: [chiave],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['valore'] as String? : null;
  }

  Future<void> salvaDatiGateway(List<Map<String, dynamic>> records) async {
    final db = await database;
    for (final r in records) {
      final ts = DateTime.fromMillisecondsSinceEpoch(
        (r['timestamp'] as int) * 1000,
      );
      await db.insert('storico', {
        'tag_id': r['tag_id'],
        'timestamp': ts.toIso8601String(),
        'boot_count': 0,
        'battery_pct': r['battery_pct'],
        'battery_mv': 0,
        'temperature': r['temperature'],
        'rssi': r['rssi'],
      });
    }
  }
}

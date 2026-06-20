import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static const String _chiaveNumeroMaster = 'numero_master';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'greggesmart.db');

    final db = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await _creaTabelle(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 5) {
          final info = await db.rawQuery('PRAGMA table_info(storico)');
          final hasImportedAt = info.any((row) => row['name'] == 'imported_at');
          if (!hasImportedAt) {
            await db.execute('ALTER TABLE storico ADD COLUMN imported_at TEXT');
          }
        }

        if (oldVersion < 6) {
          final info = await db.rawQuery('PRAGMA table_info(storico)');
          final hasLatitude = info.any((row) => row['name'] == 'latitude');
          final hasLongitude = info.any((row) => row['name'] == 'longitude');
          final hasGpsValid = info.any((row) => row['name'] == 'gps_valid');
          if (!hasLatitude) {
            await db.execute('ALTER TABLE storico ADD COLUMN latitude REAL');
          }
          if (!hasLongitude) {
            await db.execute('ALTER TABLE storico ADD COLUMN longitude REAL');
          }
          if (!hasGpsValid) {
            await db.execute(
              'ALTER TABLE storico ADD COLUMN gps_valid INTEGER DEFAULT 0',
            );
          }
        }
      },
    );

    await _assicuraColonnaMasterId(db);
    await _assicuraColonneStoricoGps(db);
    return db;
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
        master_id INTEGER,
        timestamp TEXT NOT NULL,
        imported_at TEXT,
        latitude REAL,
        longitude REAL,
        gps_valid INTEGER DEFAULT 0,
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

  Future<void> _assicuraColonnaMasterId(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(storico)');
    final hasMasterId = info.any((row) => row['name'] == 'master_id');
    if (!hasMasterId) {
      await db.execute('ALTER TABLE storico ADD COLUMN master_id INTEGER');
    }
  }

  Future<void> _assicuraColonneStoricoGps(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(storico)');
    final hasLatitude = info.any((row) => row['name'] == 'latitude');
    final hasLongitude = info.any((row) => row['name'] == 'longitude');
    final hasGpsValid = info.any((row) => row['name'] == 'gps_valid');

    if (!hasLatitude) {
      await db.execute('ALTER TABLE storico ADD COLUMN latitude REAL');
    }
    if (!hasLongitude) {
      await db.execute('ALTER TABLE storico ADD COLUMN longitude REAL');
    }
    if (!hasGpsValid) {
      await db.execute(
        'ALTER TABLE storico ADD COLUMN gps_valid INTEGER DEFAULT 0',
      );
    }
  }

  // ── STORICO ─────────────────────────────────────────

  Future<void> salvaTrasmissione({
    required int tagId,
    int? masterId,
    double? latitude,
    double? longitude,
    bool gpsValid = false,
    required int bootCount,
    required int batteryPct,
    required int batteryMv,
    required int temperature,
    required int rssi,
  }) async {
    final db = await database;
    await db.insert('storico', {
      'tag_id': tagId,
      'master_id': masterId,
      'timestamp': DateTime.now().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'gps_valid': gpsValid ? 1 : 0,
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

  Future<void> salvaNumeroMaster(int numeroMaster) async {
    await salvaConfigurazione(_chiaveNumeroMaster, numeroMaster.toString());
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

  Future<int> getNumeroMaster() async {
    final valore = await getConfigurazione(_chiaveNumeroMaster);
    return int.tryParse(valore ?? '0') ?? 0;
  }

  Future<bool> isModalitaIbrida() async {
    return (await getNumeroMaster()) > 0;
  }

  Future<void> salvaDatiGateway(List<Map<String, dynamic>> records) async {
    final db = await database;
    final importedAt = DateTime.now().toIso8601String();

    for (final r in records) {
      final rawMasterId = r['master_id'];
      final masterId = rawMasterId is int
          ? (rawMasterId > 0 ? rawMasterId : null)
          : int.tryParse('$rawMasterId');

      final ts = DateTime.fromMillisecondsSinceEpoch(
        (r['timestamp'] as int) * 1000,
      );
      await db.insert('storico', {
        'tag_id': r['tag_id'],
        'master_id': (masterId != null && masterId > 0) ? masterId : null,
        'timestamp': ts.toIso8601String(),
        'imported_at': importedAt,
        'latitude': r['latitude'],
        'longitude': r['longitude'],
        'gps_valid': (r['gps_valid'] == true) ? 1 : 0,
        'boot_count': 0,
        'battery_pct': r['battery_pct'],
        'battery_mv': 0,
        'temperature': r['temperature'],
        'rssi': r['rssi'],
      });
    }
  }

  Future<Map<int, int>> getUltimoMasterPerSlave() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT tag_id, master_id, rssi, imported_at, timestamp, gps_valid
      FROM storico
      WHERE master_id IS NOT NULL AND master_id > 0
      ORDER BY
        tag_id ASC,
        COALESCE(gps_valid, 0) DESC,
        COALESCE(imported_at, timestamp) DESC,
        timestamp DESC,
        rssi DESC,
        id DESC
    ''');

    final mappa = <int, int>{};
    for (final row in rows) {
      final tagId = row['tag_id'] as int?;
      final masterId = row['master_id'] as int?;
      if (tagId == null || masterId == null) continue;
      mappa.putIfAbsent(tagId, () => masterId);
    }
    return mappa;
  }

  Future<List<Map<String, dynamic>>> getStoricoTracciaGps({
    required DateTime from,
    required DateTime to,
    int? tagId,
  }) async {
    final db = await database;
    final args = <Object?>[from.toIso8601String(), to.toIso8601String()];
    final where = StringBuffer('''
      s.timestamp >= ?
      AND s.timestamp <= ?
      AND COALESCE(s.gps_valid, 0) = 1
      AND s.latitude IS NOT NULL
      AND s.longitude IS NOT NULL
    ''');

    if (tagId != null) {
      where.write(' AND s.tag_id = ?');
      args.add(tagId);
    }

    return db.rawQuery('''
      SELECT
        s.id,
        s.tag_id,
        s.master_id,
        s.timestamp,
        s.latitude,
        s.longitude,
        s.rssi,
        p.nome AS pecora_nome,
        m.nome AS master_nome
      FROM storico s
      LEFT JOIN pecore p ON p.tag_id = s.tag_id
      LEFT JOIN master m ON m.tag_id = s.master_id
      WHERE ${where.toString()}
      ORDER BY s.timestamp ASC, s.id ASC
      ''', args);
  }
}

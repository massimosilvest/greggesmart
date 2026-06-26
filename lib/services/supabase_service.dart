import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import 'database_service.dart';

class SupabaseService {
  SupabaseService({DatabaseService? databaseService})
    : _db = databaseService ?? DatabaseService();

  static bool _initialized = false;
  static const String _cfgPendingSyncCount = 'supabase_pending_sync_count';
  static const String _cfgPendingSyncSince = 'supabase_pending_sync_since';
  static const String _cfgLastSyncAt = 'supabase_last_sync_at';
  static const String _cfgLastStoricoSyncedId =
      'supabase_last_storico_synced_local_id';

  final DatabaseService _db;

  bool get isConfigured => SupabaseConfig.isConfigured;

  Future<void> _ensureSupabaseReady() async {
    if (!SupabaseConfig.hasValidUrl) {
      throw Exception(
        'URL Supabase non valido: ${SupabaseConfig.url}. Usa formato https://<project-ref>.supabase.co',
      );
    }

    if (SupabaseConfig.anonKey.trim().isEmpty) {
      throw Exception('Anon key Supabase mancante');
    }

    if (_initialized) return;

    try {
      await Supabase.initialize(
        url: SupabaseConfig.normalizedUrl,
        publishableKey: SupabaseConfig.anonKey.trim(),
      );
      _initialized = true;
    } catch (e) {
      final msg = '$e';
      // Evita crash in caso di doppia init durante hot reload/restart.
      if (msg.toLowerCase().contains('already initialized')) {
        debugPrint('Supabase init warning: $e');
        _initialized = true;
        return;
      }
      rethrow;
    }
  }

  Future<String> testConnection() async {
    if (!isConfigured) {
      throw Exception('Supabase non configurato. Compila supabase_config.dart');
    }

    await _ensureSupabaseReady();

    final client = Supabase.instance.client;
    // Query minimale per verificare che API key e progetto siano validi.
    await client.from('app_configurazione').select('chiave').limit(1);
    return 'Connessione Supabase OK';
  }

  Future<bool> hasDataCoverage() async {
    final host = SupabaseConfig.parsedUrl?.host;
    if (host == null || host.trim().isEmpty) return false;

    if (kIsWeb) {
      // Sul web non usiamo dart:io; proviamo direttamente una query veloce.
      try {
        await _ensureSupabaseReady();
        await Supabase.instance.client
            .from('app_configurazione')
            .select('chiave')
            .limit(1);
        return true;
      } catch (_) {
        return false;
      }
    }

    try {
      final result = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 3),
      );
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int> getPendingSyncCount() async {
    final raw = await _db.getConfigurazione(_cfgPendingSyncCount);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<CloudSyncResult> syncAfterGatewayWithFallback() async {
    if (!isConfigured) {
      return CloudSyncResult(
        status: CloudSyncStatus.notConfigured,
        message: 'Supabase non configurato',
        pendingCount: await getPendingSyncCount(),
      );
    }

    final online = await hasDataCoverage();
    if (!online) {
      final pending = await _incrementPendingSync();
      return CloudSyncResult(
        status: CloudSyncStatus.queuedOffline,
        message: 'Nessuna copertura dati: sync in coda',
        pendingCount: pending,
      );
    }

    try {
      final report = await syncDeltaToCloud();
      await _setPendingSyncCount(0);
      await _db.salvaConfigurazione(
        _cfgLastSyncAt,
        DateTime.now().toIso8601String(),
      );
      return CloudSyncResult(
        status: CloudSyncStatus.synced,
        message: 'Sync cloud completata',
        report: report,
        pendingCount: 0,
      );
    } catch (e) {
      final pending = await _incrementPendingSync();
      return CloudSyncResult(
        status: CloudSyncStatus.queuedOffline,
        message: 'Sync fallita, messa in coda: $e',
        pendingCount: pending,
      );
    }
  }

  Future<CloudSyncResult?> retryPendingIfOnline() async {
    final pending = await getPendingSyncCount();
    if (pending <= 0) return null;

    final online = await hasDataCoverage();
    if (!online) {
      return CloudSyncResult(
        status: CloudSyncStatus.queuedOffline,
        message: 'Sync ancora in coda: niente copertura dati',
        pendingCount: pending,
      );
    }

    try {
      final report = await syncDeltaToCloud();
      await _setPendingSyncCount(0);
      await _db.salvaConfigurazione(
        _cfgLastSyncAt,
        DateTime.now().toIso8601String(),
      );
      return CloudSyncResult(
        status: CloudSyncStatus.synced,
        message: 'Sync coda completata',
        report: report,
        pendingCount: 0,
      );
    } catch (e) {
      return CloudSyncResult(
        status: CloudSyncStatus.queuedOffline,
        message: 'Sync coda fallita: $e',
        pendingCount: pending,
      );
    }
  }

  Future<SyncReport> syncAllToCloud() async {
    if (!isConfigured) {
      throw Exception('Supabase non configurato. Compila supabase_config.dart');
    }

    await _ensureSupabaseReady();

    final tenantId = await _ensureTenantId();
    final client = Supabase.instance.client;

    final pecore = await _db.getPecore();
    final master = await _db.getMaster();
    final storico = await _db.getStoricoCompleto();
    final configurazione = await _db.getTuttaConfigurazione();

    if (pecore.isNotEmpty) {
      final rows = pecore
          .map(
            (row) => {
              'tenant_id': tenantId,
              'tag_id': row['tag_id'],
              'nome': row['nome'],
              'rfid': row['rfid'],
              'note': row['note'],
              'created_at': row['created_at'],
            },
          )
          .toList();
      await client.from('app_pecore').upsert(rows, onConflict: 'tenant_id,tag_id');
    }

    if (master.isNotEmpty) {
      final rows = master
          .map(
            (row) => {
              'tenant_id': tenantId,
              'tag_id': row['tag_id'],
              'nome': row['nome'],
              'rfid': row['rfid'],
              'note': row['note'],
              'created_at': row['created_at'],
            },
          )
          .toList();
      await client.from('app_master').upsert(rows, onConflict: 'tenant_id,tag_id');
    }

    if (storico.isNotEmpty) {
      final rows = storico
          .map(
            (row) => {
              'tenant_id': tenantId,
              'local_id': row['id'],
              'tag_id': row['tag_id'],
              'master_id': row['master_id'],
              'timestamp': row['timestamp'],
              'imported_at': row['imported_at'],
              'latitude': row['latitude'],
              'longitude': row['longitude'],
              'gps_valid': row['gps_valid'],
              'no_tag_seen': row['no_tag_seen'],
              'wake_del_ciclo': row['wake_del_ciclo'],
              'boot_count': row['boot_count'],
              'battery_pct': row['battery_pct'],
              'battery_mv': row['battery_mv'],
              'temperature': row['temperature'],
              'rssi': row['rssi'],
            },
          )
          .toList();
      await client.from('app_storico').upsert(rows, onConflict: 'tenant_id,local_id');
    }

    if (configurazione.isNotEmpty) {
      final rows = configurazione
          .map(
            (row) => {
              'tenant_id': tenantId,
              'chiave': row['chiave'],
              'valore': row['valore'],
            },
          )
          .toList();
      await client
          .from('app_configurazione')
          .upsert(rows, onConflict: 'tenant_id,chiave');
    }

    return SyncReport(
      tenantId: tenantId,
      pecoreCount: pecore.length,
      masterCount: master.length,
      storicoCount: storico.length,
      configurazioneCount: configurazione.length,
    );
  }

  Future<SyncReport> syncDeltaToCloud() async {
    if (!isConfigured) {
      throw Exception('Supabase non configurato. Compila supabase_config.dart');
    }

    await _ensureSupabaseReady();

    final tenantId = await _ensureTenantId();
    final client = Supabase.instance.client;

    final pecore = await _db.getPecore();
    final master = await _db.getMaster();
    final configurazione = await _db.getTuttaConfigurazione();

    if (pecore.isNotEmpty) {
      final rows = pecore
          .map(
            (row) => {
              'tenant_id': tenantId,
              'tag_id': row['tag_id'],
              'nome': row['nome'],
              'rfid': row['rfid'],
              'note': row['note'],
              'created_at': row['created_at'],
            },
          )
          .toList();
      await client.from('app_pecore').upsert(rows, onConflict: 'tenant_id,tag_id');
    }

    if (master.isNotEmpty) {
      final rows = master
          .map(
            (row) => {
              'tenant_id': tenantId,
              'tag_id': row['tag_id'],
              'nome': row['nome'],
              'rfid': row['rfid'],
              'note': row['note'],
              'created_at': row['created_at'],
            },
          )
          .toList();
      await client.from('app_master').upsert(rows, onConflict: 'tenant_id,tag_id');
    }

    int storicoSynced = 0;
    var cursor = await _getLastStoricoSyncedId();

    while (true) {
      final batch = await _db.getStoricoDaId(cursor, limit: 500);
      if (batch.isEmpty) break;

      final rows = batch
          .map(
            (row) => {
              'tenant_id': tenantId,
              'local_id': row['id'],
              'tag_id': row['tag_id'],
              'master_id': row['master_id'],
              'timestamp': row['timestamp'],
              'imported_at': row['imported_at'],
              'latitude': row['latitude'],
              'longitude': row['longitude'],
              'gps_valid': row['gps_valid'],
              'no_tag_seen': row['no_tag_seen'],
              'wake_del_ciclo': row['wake_del_ciclo'],
              'boot_count': row['boot_count'],
              'battery_pct': row['battery_pct'],
              'battery_mv': row['battery_mv'],
              'temperature': row['temperature'],
              'rssi': row['rssi'],
            },
          )
          .toList();

      await client.from('app_storico').upsert(rows, onConflict: 'tenant_id,local_id');
      storicoSynced += rows.length;

      final lastIdRaw = batch.last['id'];
      final lastId = lastIdRaw is int ? lastIdRaw : int.tryParse('$lastIdRaw') ?? cursor;
      cursor = lastId;
      await _setLastStoricoSyncedId(cursor);

      if (batch.length < 500) break;
    }

    if (configurazione.isNotEmpty) {
      final rows = configurazione
          .map(
            (row) => {
              'tenant_id': tenantId,
              'chiave': row['chiave'],
              'valore': row['valore'],
            },
          )
          .toList();
      await client
          .from('app_configurazione')
          .upsert(rows, onConflict: 'tenant_id,chiave');
    }

    return SyncReport(
      tenantId: tenantId,
      pecoreCount: pecore.length,
      masterCount: master.length,
      storicoCount: storicoSynced,
      configurazioneCount: configurazione.length,
    );
  }

  Future<String> _ensureTenantId() async {
    final existing = await _db.getConfigurazione('supabase_tenant_id');
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final random = Random();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final salt = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    final tenantId = 'tenant_${timestamp}_$salt';
    await _db.salvaConfigurazione('supabase_tenant_id', tenantId);
    return tenantId;
  }

  Future<int> _incrementPendingSync() async {
    final current = await getPendingSyncCount();
    final next = current + 1;
    await _db.salvaConfigurazione(_cfgPendingSyncCount, next.toString());
    final since = await _db.getConfigurazione(_cfgPendingSyncSince);
    if (since == null || since.trim().isEmpty) {
      await _db.salvaConfigurazione(
        _cfgPendingSyncSince,
        DateTime.now().toIso8601String(),
      );
    }
    return next;
  }

  Future<void> _setPendingSyncCount(int count) async {
    await _db.salvaConfigurazione(_cfgPendingSyncCount, '$count');
    if (count <= 0) {
      await _db.salvaConfigurazione(_cfgPendingSyncSince, '');
    }
  }

  Future<int> _getLastStoricoSyncedId() async {
    final raw = await _db.getConfigurazione(_cfgLastStoricoSyncedId);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  Future<void> _setLastStoricoSyncedId(int id) async {
    await _db.salvaConfigurazione(_cfgLastStoricoSyncedId, '$id');
  }

  Future<void> resetStoricoSyncCursor() async {
    await _db.salvaConfigurazione(_cfgLastStoricoSyncedId, '0');
  }
}

enum CloudSyncStatus { synced, queuedOffline, notConfigured }

class CloudSyncResult {
  CloudSyncResult({
    required this.status,
    required this.message,
    required this.pendingCount,
    this.report,
  });

  final CloudSyncStatus status;
  final String message;
  final int pendingCount;
  final SyncReport? report;
}

class SyncReport {
  SyncReport({
    required this.tenantId,
    required this.pecoreCount,
    required this.masterCount,
    required this.storicoCount,
    required this.configurazioneCount,
  });

  final String tenantId;
  final int pecoreCount;
  final int masterCount;
  final int storicoCount;
  final int configurazioneCount;
}

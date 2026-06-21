import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/tag_device.dart';

class GatewayService {
  static const String serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String cmdCharUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  static const String dataCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  static const Duration _scanTimeout = Duration(seconds: 20);
  static const Duration _connectTimeout = Duration(seconds: 30);
  static const Duration _readChunkPause = Duration(milliseconds: 250);
  static const int _maxReadCycles = 18;

  Future<GatewayDownloadResult> scaricaDaGateway({
    required int masterId,
    required int expectedMasterCount,
    bool allowClearOnPartial = false,
    required void Function(String status) onStatus,
  }) async {
    debugPrint('=== INIZIO GATEWAY DOWNLOAD ===');
    debugPrint('Master ID: 0x${masterId.toRadixString(16).toUpperCase()}');
    debugPrint('Expected Masters: $expectedMasterCount');

    onStatus("Ricerca master nelle vicinanze...");

    BluetoothDevice? targetDevice;
    final foundTarget = Completer<void>();
    final masterIdHex = masterId.toRadixString(16).toLowerCase();
    var devicesSeen = 0;
    final ultimiNomi = <String>[];
    debugPrint('DEBUG: cerco master con hex: $masterIdHex');
    onStatus(
      'Scansione BLE avviata (target master: 0x${masterId.toRadixString(16).toUpperCase()})',
    );

    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        final remoteId = r.device.remoteId.toString();
        final normalizedRemoteId = remoteId.replaceAll(':', '').toLowerCase();
        final normalizedName = name.toLowerCase();
        final rawPayload = r.advertisementData.manufacturerData[0xFFFF];
        final parsedTag = rawPayload == null
            ? null
            : TagDevice.fromManufacturerData(rawPayload, r.rssi);
        final manufacturerKeys = r.advertisementData.manufacturerData.keys
            .map((k) => '0x${k.toRadixString(16)}')
            .join(', ');

        devicesSeen++;
        final label = name.isNotEmpty ? name : remoteId;
        ultimiNomi.remove(label);
        ultimiNomi.add(label);
        if (ultimiNomi.length > 4) {
          ultimiNomi.removeAt(0);
        }

        debugPrint(
          'DEBUG: candidate device name="$name" id=$remoteId mfg=[$manufacturerKeys]',
        );

        onStatus(
          'Scansione BLE: $devicesSeen visti (${ultimiNomi.join(' | ')})',
        );

        final matchesPayload =
            parsedTag != null && parsedTag.isMaster && parsedTag.tagId == masterId;
        final matchesName = normalizedName.contains('0x$masterIdHex');
        final matchesAddress = normalizedRemoteId.endsWith(masterIdHex);

        if (matchesPayload || matchesName || matchesAddress) {
          debugPrint('DEBUG: MATCH! device: $name id=$remoteId');
          onStatus(
            name.isNotEmpty
                ? 'Master trovato: $name'
                : 'Master trovato: $remoteId',
          );
          targetDevice = r.device;
          if (!foundTarget.isCompleted) {
            foundTarget.complete();
          }
          break;
        }
      }
    });

    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 500));
    await FlutterBluePlus.startScan(timeout: _scanTimeout);
    await Future.any([foundTarget.future, Future.delayed(_scanTimeout)]);
    await FlutterBluePlus.stopScan();
    await subscription.cancel();

    if (targetDevice == null) {
      onStatus(
        'Master non trovato: nessun device con nome o indirizzo che contenga $masterIdHex',
      );
      throw Exception("Master non trovato");
    }

    onStatus("Connessione al master...");
    await targetDevice!.connect(timeout: _connectTimeout);

    onStatus("Scoperta servizi...");
    final services = await targetDevice!.discoverServices();

    BluetoothCharacteristic? cmdChar;
    BluetoothCharacteristic? dataChar;

    for (final service in services) {
      debugPrint('DEBUG: servizio trovato: ${service.uuid}');
      if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        for (final c in service.characteristics) {
          if (c.uuid.toString().toLowerCase() == cmdCharUuid.toLowerCase()) {
            cmdChar = c;
          }
          if (c.uuid.toString().toLowerCase() == dataCharUuid.toLowerCase()) {
            dataChar = c;
          }
        }
      }
    }

    if (cmdChar == null || dataChar == null) {
      await targetDevice!.disconnect();
      onStatus("Servizio gateway non trovato sul master.");
      throw Exception("Servizio non trovato");
    }

    onStatus("Attivazione modalità gateway...");
    await cmdChar.write("GATEWAY_ON".codeUnits, withoutResponse: false);
    debugPrint('DEBUG: Comando inviato: GATEWAY_ON');

    await Future.delayed(const Duration(seconds: 2));

    onStatus("Scaricamento dati...");
    final dataString = await _readGatewayDump(dataChar, onStatus);
    debugPrint('DEBUG: Dump ricevuto (${dataString.length} chars):');
    debugPrint(dataString);
    debugPrint('DEBUG: === Fine dump raw ===');

    final records = _parseDati(dataString);
    debugPrint('DEBUG: Record parsati: ${records.length}');
    for (final r in records) {
      debugPrint(
        'DEBUG:   Tag 0x${(r['tag_id'] as int?)?.toRadixString(16).toUpperCase() ?? '?'}'
        ' -> Master 0x${(r['master_id'] as int?)?.toRadixString(16).toUpperCase() ?? 'null'}'
        ' | TS: ${r['timestamp']} | GPS: ${r['gps_valid']} @ (${r['latitude']}, ${r['longitude']})',
      );
    }

    final masterIdsNelDump = records
        .map((r) => r['master_id'])
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();

    final expected = expectedMasterCount <= 0 ? 1 : expectedMasterCount;
    final allineatoSuTuttiIMaster = masterIdsNelDump.length >= expected;
    final canClear = allineatoSuTuttiIMaster || allowClearOnPartial;

    debugPrint('DEBUG: Master IDs nel dump: ${masterIdsNelDump.length}/$expected');
    debugPrint('DEBUG: canClear: $canClear');

    if (canClear) {
      onStatus("Conferma e pulizia memoria master...");
      await cmdChar.write("CLEAR_DB".codeUnits, withoutResponse: false);
      debugPrint('DEBUG: Comando inviato: CLEAR_DB');
    } else {
      onStatus(
        'Memoria NON azzerata: dump da ${masterIdsNelDump.length}/$expected master.',
      );
    }

    await targetDevice!.disconnect();
    debugPrint('=== FINE GATEWAY DOWNLOAD ===\n');
    onStatus(
      canClear
          ? "Download completato! ${records.length} record ricevuti."
          : "Download completato senza reset memoria (${records.length} record).",
    );

    return GatewayDownloadResult(
      records: records,
      clearSent: canClear,
      expectedMasterCount: expected,
      masterIdsInDump: masterIdsNelDump,
    );
  }

  Future<String> _readGatewayDump(
    BluetoothCharacteristic dataChar,
    void Function(String status) onStatus,
  ) async {
    final chunks = <String>[];
    final seenChunks = <String>{};
    var cicliSenzaNuovi = 0;

    for (var i = 0; i < _maxReadCycles; i++) {
      final rawData = await dataChar.read();
      final chunk = String.fromCharCodes(rawData).trim();

      if (chunk.isEmpty) {
        cicliSenzaNuovi++;
      } else {
        final isNuovo = seenChunks.add(chunk);
        if (isNuovo) {
          chunks.add(chunk);
          cicliSenzaNuovi = 0;
          onStatus('Scaricamento dati... blocchi ricevuti: ${chunks.length}');

          if (chunk.contains('END') || chunk.contains('DONE')) {
            break;
          }
        } else {
          cicliSenzaNuovi++;
        }
      }

      if (cicliSenzaNuovi >= 3) {
        break;
      }

      await Future.delayed(_readChunkPause);
    }

    final unito = chunks.join('');
    return unito.replaceAll('END', '').replaceAll('DONE', '').trim();
  }

  List<Map<String, dynamic>> _parseDati(String raw) {
    final records = <Map<String, dynamic>>[];
    final righe = raw.split(';').where((r) => r.trim().isNotEmpty);

    for (final riga in righe) {
      final campi = riga.split(',');
      if (campi.length < 9) continue;

      records.add({
        'tag_id': int.tryParse(campi[0]) ?? 0,
        'master_id': int.tryParse(campi[1]) ?? 0,
        'rssi': int.tryParse(campi[2]) ?? 0,
        'battery_pct': int.tryParse(campi[3]) ?? 0,
        'temperature': int.tryParse(campi[4]) ?? 0,
        'latitude': double.tryParse(campi[5]) ?? 0.0,
        'longitude': double.tryParse(campi[6]) ?? 0.0,
        'gps_valid': campi[7] == '1',
        'timestamp': int.tryParse(campi[8]) ?? 0,
      });
    }

    return records;
  }
}

class GatewayDownloadResult {
  GatewayDownloadResult({
    required this.records,
    required this.clearSent,
    required this.expectedMasterCount,
    required this.masterIdsInDump,
  });

  final List<Map<String, dynamic>> records;
  final bool clearSent;
  final int expectedMasterCount;
  final Set<int> masterIdsInDump;
}

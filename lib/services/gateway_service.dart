import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class GatewayService {
  static const String serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String cmdCharUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  static const String dataCharUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  Future<List<Map<String, dynamic>>> scaricaDaGateway({
    required int masterId,
    required void Function(String status) onStatus,
  }) async {
    onStatus("Ricerca master nelle vicinanze...");

    BluetoothDevice? targetDevice;
    final masterIdHex = masterId.toRadixString(16).toLowerCase();
    debugPrint('DEBUG: cerco master con hex: $masterIdHex');
    onStatus('Cerca device con nome che contenga $masterIdHex');

    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        final remoteId = r.device.remoteId.toString();
        final normalizedRemoteId = remoteId.replaceAll(':', '').toLowerCase();
        final manufacturerKeys = r.advertisementData.manufacturerData.keys
            .map((k) => '0x${k.toRadixString(16)}')
            .join(', ');

        debugPrint(
          'DEBUG: candidate device name="$name" id=$remoteId mfg=[$manufacturerKeys]',
        );

        if (name.isNotEmpty) {
          onStatus('Visto $name');
        }

        final matchesName = name.toLowerCase().contains(masterIdHex);
        final matchesAddress = normalizedRemoteId.contains(masterIdHex);

        if (matchesName || matchesAddress) {
          debugPrint('DEBUG: MATCH! device: $name id=$remoteId');
          onStatus(
            name.isNotEmpty
                ? 'Master trovato: $name'
                : 'Master trovato: $remoteId',
          );
          targetDevice = r.device;
        }
      }
    });

    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 500));
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await Future.delayed(const Duration(seconds: 10));
    await FlutterBluePlus.stopScan();
    await subscription.cancel();

    if (targetDevice == null) {
      onStatus(
        'Master non trovato: nessun device con nome o indirizzo che contenga $masterIdHex',
      );
      throw Exception("Master non trovato");
    }

    onStatus("Connessione al master...");
    await targetDevice!.connect(timeout: const Duration(seconds: 10));

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

    await Future.delayed(const Duration(seconds: 2));

    onStatus("Scaricamento dati...");
    final rawData = await dataChar.read();
    final dataString = String.fromCharCodes(rawData);

    final records = _parseDati(dataString);

    onStatus("Conferma e pulizia memoria master...");
    await cmdChar.write("CLEAR_DB".codeUnits, withoutResponse: false);

    await targetDevice!.disconnect();
    onStatus("Download completato! ${records.length} record ricevuti.");

    return records;
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

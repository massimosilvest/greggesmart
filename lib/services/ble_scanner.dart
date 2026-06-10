import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/tag_device.dart';
import 'database_service.dart';

class BleScanner {
  final _tagsController = StreamController<Map<int, TagDevice>>.broadcast();

  Stream<Map<int, TagDevice>> get tagsStream => _tagsController.stream;

  final Map<int, TagDevice> _tags = {};
  StreamSubscription? _scanSubscription;
  bool _shouldScan = false;
  final _db = DatabaseService();

  void startScan() {
    _shouldScan = true;
    _doScan();
  }

  Future<void> _doScan() async {
    while (_shouldScan) {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 25),
        continuousUpdates: true,
      );

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          _parseResult(result);
        }
      });

      await FlutterBluePlus.isScanning.where((val) => val == false).first;

      if (_shouldScan) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  void _parseResult(ScanResult result) {
    final manData = result.advertisementData.manufacturerData;
    if (manData.isEmpty) return;

    final raw = manData[0xFFFF];
    if (raw == null) return;

    final newTag = TagDevice.fromManufacturerData(raw, result.rssi);
    if (newTag == null) return;

    final existing = _tags[newTag.tagId];
    if (existing != null) {
      // Salva nel DB solo se bootCount è cambiato
      if (newTag.bootCount != existing.bootCount) {
        _db.salvaTrasmissione(
          tagId: newTag.tagId,
          bootCount: newTag.bootCount,
          batteryPct: newTag.batteryPct,
          batteryMv: newTag.batteryMv,
          temperature: newTag.temperature,
          rssi: newTag.rssi,
        );
      }
      _tags[newTag.tagId] = existing.copyWithNewReading(
        batteryPct: newTag.batteryPct,
        batteryMv: newTag.batteryMv,
        flags: newTag.flags,
        bootCount: newTag.bootCount,
        temperature: newTag.temperature,
        rssi: newTag.rssi,
      );
    } else {
      // Prima volta che vediamo questo TAG
      _db.salvaTrasmissione(
        tagId: newTag.tagId,
        bootCount: newTag.bootCount,
        batteryPct: newTag.batteryPct,
        batteryMv: newTag.batteryMv,
        temperature: newTag.temperature,
        rssi: newTag.rssi,
      );
      _tags[newTag.tagId] = newTag;
    }

    _tagsController.add(Map.from(_tags));
  }

  void stopScan() {
    _shouldScan = false;
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
  }

  void dispose() {
    stopScan();
    _tagsController.close();
  }
}

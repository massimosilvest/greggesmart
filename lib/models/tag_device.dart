import 'dart:typed_data';

class TagDevice {
  final int tagId;
  final int type; // 0=slave, 1=master
  final int batteryPct;
  final int batteryMv;
  final int flags;
  final int bootCount;
  final int temperature;
  final DateTime lastSeen;
  final int rssi;
  final int rxCount;

  // Solo master
  final double? latitude;
  final double? longitude;
  final bool gpsValid;
  final bool gatewayMode;

  TagDevice({
    required this.tagId,
    required this.type,
    required this.batteryPct,
    required this.batteryMv,
    required this.flags,
    required this.bootCount,
    required this.temperature,
    required this.lastSeen,
    required this.rssi,
    this.rxCount = 0,
    this.latitude,
    this.longitude,
    this.gpsValid = false,
    this.gatewayMode = false,
  });

  bool get isMaster => type == 1;
  bool get isSlave => type == 0;
  bool get isBatLow => (flags & 0x01) != 0;
  bool get isBatCritical => (flags & 0x02) != 0;
  bool get isCold => (flags & 0x04) != 0;
  bool get isColdCritical => (flags & 0x08) != 0;

  TagDevice copyWithNewReading({
    required int batteryPct,
    required int batteryMv,
    required int flags,
    required int bootCount,
    required int temperature,
    required int rssi,
    double? latitude,
    double? longitude,
    bool gpsValid = false,
    bool gatewayMode = false,
  }) {
    final newRx = bootCount != this.bootCount ? rxCount + 1 : rxCount;
    return TagDevice(
      tagId: tagId,
      type: type,
      batteryPct: batteryPct,
      batteryMv: batteryMv,
      flags: flags,
      bootCount: bootCount,
      temperature: temperature,
      lastSeen: bootCount != this.bootCount ? DateTime.now() : lastSeen,
      rssi: rssi,
      rxCount: newRx,
      latitude: latitude,
      longitude: longitude,
      gpsValid: gpsValid,
      gatewayMode: gatewayMode,
    );
  }

  // Parser slave — 17 byte
  static TagDevice? _fromSlave(List<int> data, int rssi) {
    if (data.length < 17) return null;

    int xor = 0;
    for (int i = 0; i < 13; i++) {
      xor ^= data[i];
    }
    if (xor != data[13]) return null;

    return TagDevice(
      tagId: data[1] | (data[2] << 8),
      type: 0,
      batteryPct: data[4],
      batteryMv: (data[5] << 8) | data[6],
      flags: data[7],
      bootCount: (data[8] << 8) | data[9],
      temperature: data[12].toSigned(8),
      lastSeen: DateTime.now(),
      rssi: rssi,
      rxCount: 1,
    );
  }

  // Parser master — 25 byte
  static TagDevice? _fromMaster(List<int> data, int rssi) {
    if (data.length < 25) return null;

    // XOR checksum su byte 0..20
    int xor = 0;
    for (int i = 0; i < 21; i++) {
      xor ^= data[i];
    }
    if (xor != data[21]) return null;

    // Estrai latitude float 4 byte (byte 13-16)
    final latBytes = data.sublist(13, 17);
    final lonBytes = data.sublist(17, 21);
    final lat = _bytesToFloat(latBytes);
    final lon = _bytesToFloat(lonBytes);

    final flags = data[7];
    final gpsValid = (flags & 0x10) != 0;
    final gatewayMode = (flags & 0x20) != 0;

    return TagDevice(
      tagId: data[1] | (data[2] << 8),
      type: 1,
      batteryPct: data[4],
      batteryMv: (data[5] << 8) | data[6],
      flags: flags,
      bootCount: (data[8] << 8) | data[9],
      temperature: data[12].toSigned(8),
      lastSeen: DateTime.now(),
      rssi: rssi,
      rxCount: 1,
      latitude: lat,
      longitude: lon,
      gpsValid: gpsValid,
      gatewayMode: gatewayMode,
    );
  }

  // Converte 4 byte in float (little endian)
  static double _bytesToFloat(List<int> bytes) {
    if (bytes.length < 4) return 0.0;
    final bd = ByteData(4);
    for (int i = 0; i < 4; i++) {
      bd.setUint8(i, bytes[i] & 0xFF);
    }
    return bd.getFloat32(0, Endian.little);
  }

  // Parser principale — decide slave o master
  static TagDevice? fromManufacturerData(List<int> data, int rssi) {
    if (data.isEmpty) return null;
    if (data[0] != 0xA1) return null;
    if (data.length < 4) return null;

    final type = data[3];
    if (type == 0) return _fromSlave(data, rssi);
    if (type == 1) return _fromMaster(data, rssi);
    return null;
  }

  String get tagIdHex =>
      '0x${tagId.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  String get tipoStringa => isMaster ? 'Master' : 'Slave';
}

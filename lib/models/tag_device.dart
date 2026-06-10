class TagDevice {
  final int tagId;
  final int type;
  final int batteryPct;
  final int batteryMv;
  final int flags;
  final int bootCount;
  final int temperature;
  final DateTime lastSeen;
  final int rssi;
  final int rxCount;

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
  });

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
  }) {
    // Incrementa RX solo se il bootCount è cambiato
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
    );
  }

  static TagDevice? fromManufacturerData(List<int> data, int rssi) {
    if (data.length < 17) return null;
    if (data[0] != 0xA1) return null;

    int xor = 0;
    for (int i = 0; i < 13; i++) {
      xor ^= data[i];
    }
    if (xor != data[13]) return null;

    return TagDevice(
      tagId: data[1] | (data[2] << 8),
      type: data[3],
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

  String get tagIdHex =>
      '0x${tagId.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

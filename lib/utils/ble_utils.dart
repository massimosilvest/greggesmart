import 'package:flutter/material.dart';
import 'dart:math';

class BleUtils {
  static double stimaDistanza(int rssi) {
    const txPower = -59;
    const n = 2.5;
    if (rssi == 0) return -1;
    return pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  static String distanzaStringa(int rssi) {
    final d = stimaDistanza(rssi);
    if (d < 0) return '?';
    if (d < 1) return '<1m';
    if (d < 10) return '~${d.toStringAsFixed(0)}m';
    if (d < 100) return '~${(d / 5).round() * 5}m';
    return '>100m';
  }

  static TagStato statoTag(DateTime lastSeen, int flags) {
    final secondi = DateTime.now().difference(lastSeen).inSeconds;
    final batCrit = (flags & 0x02) != 0;
    final batLow = (flags & 0x01) != 0;

    int soglia1, soglia2, soglia3;
    if (batCrit) {
      soglia1 = 180;
      soglia2 = 360;
      soglia3 = 900;
    } else if (batLow) {
      soglia1 = 120;
      soglia2 = 240;
      soglia3 = 600;
    } else {
      soglia1 = 60;
      soglia2 = 120;
      soglia3 = 300;
    }

    if (secondi < soglia1) return TagStato.ok;
    if (secondi < soglia2) return TagStato.attenzione;
    if (secondi < soglia3) return TagStato.lontano;
    return TagStato.perso;
  }

  // Stato master basato su lastSeen (null = non visto)
  static MasterStato statoMaster(DateTime? lastSeen) {
    if (lastSeen == null) return MasterStato.offline;
    final secondi = DateTime.now().difference(lastSeen).inSeconds;
    if (secondi < 60) return MasterStato.ok;
    if (secondi < 120) return MasterStato.attenzione;
    if (secondi < 300) return MasterStato.lontano;
    return MasterStato.offline;
  }
}

enum TagStato { ok, attenzione, lontano, perso }

extension TagStatoExt on TagStato {
  String get emoji {
    switch (this) {
      case TagStato.ok:
        return '🟢';
      case TagStato.attenzione:
        return '🟡';
      case TagStato.lontano:
        return '🔴';
      case TagStato.perso:
        return '⬛';
    }
  }

  String get label {
    switch (this) {
      case TagStato.ok:
        return 'In vista';
      case TagStato.attenzione:
        return 'Attenzione';
      case TagStato.lontano:
        return 'Lontano';
      case TagStato.perso:
        return 'Perso';
    }
  }
}

enum MasterStato { ok, attenzione, lontano, offline }

extension MasterStatoExt on MasterStato {
  String get emoji {
    switch (this) {
      case MasterStato.ok:
        return '🟢';
      case MasterStato.attenzione:
        return '🟡';
      case MasterStato.lontano:
        return '🔴';
      case MasterStato.offline:
        return '⬛';
    }
  }

  String get label {
    switch (this) {
      case MasterStato.ok:
        return 'Attivo';
      case MasterStato.attenzione:
        return 'Attenzione';
      case MasterStato.lontano:
        return 'Lontano';
      case MasterStato.offline:
        return 'Offline';
    }
  }

  Color get color {
    switch (this) {
      case MasterStato.ok:
        return const Color(0xFF2D9BFF);
      case MasterStato.attenzione:
        return const Color(0xFFFFD700);
      case MasterStato.lontano:
        return const Color(0xFFFF6B35);
      case MasterStato.offline:
        return const Color(0xFF666666);
    }
  }
}

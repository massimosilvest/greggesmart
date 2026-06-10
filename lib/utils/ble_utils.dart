import 'dart:math';

class BleUtils {
  // Stima distanza da RSSI
  // TxPower: -59 dBm a 1 metro (ESP32 a potenza N0)
  // n: 2.5 path loss exponent per campo aperto
  static double stimaDistanza(int rssi) {
    const txPower = -59;
    const n = 2.5;
    if (rssi == 0) return -1;
    return pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  // Distanza formattata
  static String distanzaStringa(int rssi) {
    final d = stimaDistanza(rssi);
    if (d < 0) return '?';
    if (d < 1) return '<1m';
    if (d < 10) return '~${d.toStringAsFixed(0)}m';
    if (d < 100) return '~${(d / 5).round() * 5}m';
    return '>100m';
  }

  // Stato TAG basato su lastSeen e flags batteria
  static TagStato statoTag(DateTime lastSeen, int flags) {
    final secondi = DateTime.now().difference(lastSeen).inSeconds;
    final batCrit = (flags & 0x02) != 0;
    final batLow = (flags & 0x01) != 0;

    // Soglie adattive alla batteria
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
        return 'Lontana';
      case TagStato.perso:
        return 'Persa';
    }
  }
}

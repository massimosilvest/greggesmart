import 'package:flutter/material.dart';
import '../models/tag_device.dart';
import '../utils/ble_utils.dart';

class DettaglioMasterScreen extends StatelessWidget {
  final TagDevice tag;

  const DettaglioMasterScreen({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    final distanza = BleUtils.distanzaStringa(tag.rssi);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1F3D),
        title: Text(
          'Master ${tag.tagIdHex}',
          style: const TextStyle(color: Color(0xFF2D9BFF)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2D9BFF)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stato ───────────────────────────────────
            Card(
              color: const Color(0xFF0F1F3D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STATO',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _infoTile(
                          tag.gatewayMode ? '🔵' : '🟢',
                          tag.gatewayMode ? 'Gateway' : 'Master',
                          'Modalità',
                        ),
                        _infoTile('📶', distanza, '${tag.rssi} dBm'),
                        _infoTile(
                          tag.isBatCritical ? '🪫' : '🔋',
                          '${tag.batteryPct}%',
                          '${tag.batteryMv} mV',
                        ),
                        _infoTile('🌡️', '${tag.temperature}°C', 'Temp'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── GPS ──────────────────────────────────────
            Card(
              color: const Color(0xFF0F1F3D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _debugRow(
                      'Fix GPS',
                      tag.gpsValid ? '✅ Attivo' : '❌ No fix',
                    ),
                    if (tag.latitude != null)
                      _debugRow('Latitudine', tag.latitude!.toStringAsFixed(6)),
                    if (tag.longitude != null)
                      _debugRow(
                        'Longitudine',
                        tag.longitude!.toStringAsFixed(6),
                      ),
                    if (!tag.gpsValid)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Coordinate storiche — ultimo fix noto',
                          style: TextStyle(
                            color: Colors.white30,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Debug ────────────────────────────────────
            Card(
              color: const Color(0xFF0F1F3D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DEBUG',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _debugRow('Master ID', tag.tagIdHex),
                    _debugRow('Boot count', '${tag.bootCount}'),
                    _debugRow('TX count', '${tag.rxCount}'),
                    _debugRow('Segnale', '${tag.rssi} dBm'),
                    _debugRow(
                      'Flags',
                      '0b${tag.flags.toRadixString(2).padLeft(8, '0')}',
                    ),
                    _debugRow(
                      'Ultimo contatto',
                      '${tag.lastSeen.hour.toString().padLeft(2, '0')}:'
                          '${tag.lastSeen.minute.toString().padLeft(2, '0')}:'
                          '${tag.lastSeen.second.toString().padLeft(2, '0')}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Azioni ───────────────────────────────────
            Card(
              color: const Color(0xFF0F1F3D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AZIONI',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: null, // TODO: implementare
                        icon: const Icon(Icons.download),
                        label: const Text('SCARICA DATABASE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D9BFF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFF2D9BFF,
                          ).withOpacity(0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String emoji, String valore, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          valore,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  Widget _debugRow(String label, String valore) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          Text(
            valore,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

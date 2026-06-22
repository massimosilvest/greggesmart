import 'package:flutter/material.dart';
import '../models/tag_device.dart';
import '../screens/associa_screen.dart';
import '../screens/dettaglio_screen.dart';
import '../screens/dettaglio_master_screen.dart';
import '../utils/ble_utils.dart';

class TagCard extends StatelessWidget {
  final TagDevice tag;
  final Map<String, dynamic>? pecora;
  final Map<String, dynamic>? master;
  final VoidCallback onAggiornato;
  final VoidCallback onPausaScan;
  final VoidCallback onRiprendiScan;

  const TagCard({
    super.key,
    required this.tag,
    required this.pecora,
    required this.master,
    required this.onAggiornato,
    required this.onPausaScan,
    required this.onRiprendiScan,
  });

  Widget _batteryIcon(TagDevice tag) {
    IconData icon;
    Color color;

    if (tag.isBatCritical) {
      icon = Icons.battery_alert;
      color = Colors.red;
    } else if (tag.isBatLow) {
      icon = Icons.battery_2_bar;
      color = Colors.orange;
    } else if (tag.batteryPct > 75) {
      icon = Icons.battery_full;
      color = const Color(0xFF2DFF6E);
    } else {
      icon = Icons.battery_4_bar;
      color = const Color(0xFF2DFF6E);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 3),
        Text(
          '${tag.batteryPct}%',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (tag.isMaster) return _buildMasterCard(context);
    return _buildSlaveCard(context);
  }

  Widget _buildMasterCard(BuildContext context) {
    final distanza = BleUtils.distanzaStringa(tag.rssi);
    final nome = master?['nome'] as String? ?? tag.tagIdHex;
    final associato = master != null;
    final stato = BleUtils.statoMaster(tag.lastSeen);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DettaglioMasterScreen(
              tag: tag,
              master: master,
              onPausaScan: onPausaScan,
              onRiprendiScan: onRiprendiScan,
              onAggiornato: onAggiornato,
            ),
          ),
        );
        if (result == true) onAggiornato();
      },
      child: Card(
        color: const Color(0xFF0F1F3D),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Column(
                children: [
                  Icon(
                    tag.gatewayMode ? Icons.router : Icons.hub,
                    color: tag.gatewayMode ? Colors.amber : stato.color,
                    size: 24,
                  ),
                  Text(stato.emoji, style: const TextStyle(fontSize: 10)),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        color: stato.color,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!associato)
                      const Text(
                        'Tocca per associare',
                        style: TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                    Text(
                      tag.gpsValid
                          ? 'GPS: ${tag.latitude?.toStringAsFixed(4)}, '
                                '${tag.longitude?.toStringAsFixed(4)}'
                          : 'GPS: no fix',
                      style: TextStyle(
                        color: tag.gpsValid ? Colors.white54 : Colors.white30,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _batteryIcon(tag),
                  const SizedBox(height: 2),
                  Text(
                    distanza,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlaveCard(BuildContext context) {
    final nome = pecora?['nome'] as String? ?? tag.tagIdHex;
    final associata = pecora != null;
    final stato = BleUtils.statoTag(tag.lastSeen, tag.flags);
    final distanza = BleUtils.distanzaStringa(tag.rssi);

    return GestureDetector(
      onTap: () async {
        if (!associata) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AssociaScreen(tagId: tag.tagId, tagIdHex: tag.tagIdHex),
            ),
          );
          if (result == true) onAggiornato();
        } else {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DettaglioScreen(tag: tag, pecora: pecora!),
            ),
          );
          if (result == true) onAggiornato();
        }
      },
      child: Card(
        color: const Color(0xFF0F2318),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Text(stato.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        color: Color(0xFF2DFF6E),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!associata)
                      const Text(
                        'Tocca per associare',
                        style: TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                  ],
                ),
              ),
              _batteryIcon(tag),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    distanza,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${tag.temperature}°C',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

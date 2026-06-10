import 'package:flutter/material.dart';
import '../models/tag_device.dart';
import '../screens/associa_screen.dart';
import '../screens/dettaglio_screen.dart';
import '../utils/ble_utils.dart';

class TagCard extends StatelessWidget {
  final TagDevice tag;
  final Map<String, dynamic>? pecora;
  final VoidCallback onAggiornato;

  const TagCard({
    super.key,
    required this.tag,
    required this.pecora,
    required this.onAggiornato,
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
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 3),
        Text(
          '${tag.batteryPct}%',
          style: TextStyle(color: color, fontSize: 13),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = pecora?['nome'] as String? ?? tag.tagIdHex;
    final associata = pecora != null;
    final stato = BleUtils.statoTag(tag.lastSeen, tag.flags);
    final distanza = BleUtils.distanzaStringa(tag.rssi);

    return GestureDetector(
      onTap: () async {
        if (!associata) {
          // TAG non associato → schermata associazione
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AssociaScreen(tagId: tag.tagId, tagIdHex: tag.tagIdHex),
            ),
          );
          if (result == true) onAggiornato();
        } else {
          // TAG associato → schermata dettaglio/debug
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
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Semaforo stato
              Text(stato.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              // Nome pecora
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        color: Color(0xFF2DFF6E),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!associata)
                      const Text(
                        'Tocca per associare',
                        style: TextStyle(color: Colors.orange, fontSize: 11),
                      ),
                  ],
                ),
              ),
              // Batteria
              _batteryIcon(tag),
              const SizedBox(width: 12),
              // Distanza
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    distanza,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${tag.temperature}°C',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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

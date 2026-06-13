import 'package:flutter/material.dart';
import '../models/tag_device.dart';
import '../services/database_service.dart';
import '../utils/ble_utils.dart';
import 'associa_screen.dart';

class DettaglioScreen extends StatefulWidget {
  final TagDevice tag;
  final Map<String, dynamic> pecora;

  const DettaglioScreen({super.key, required this.tag, required this.pecora});

  @override
  State<DettaglioScreen> createState() => _DettaglioScreenState();
}

class _DettaglioScreenState extends State<DettaglioScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _storico = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _caricaStorico();
  }

  Future<void> _caricaStorico() async {
    final s = await _db.getStorico(widget.tag.tagId);
    setState(() {
      _storico = s;
      _loading = false;
    });
  }

  Future<void> _elimina() async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Elimina TAG',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        content: Text(
          'Vuoi eliminare "${widget.pecora['nome']}"?\nVerranno cancellati anche tutti i dati storici.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'ANNULLA',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (conferma == true) {
      await _db.eliminaPecora(widget.tag.tagId);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  String _formatDateTime(String iso) {
    final dt = DateTime.parse(iso);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    final pecora = widget.pecora;
    final stato = BleUtils.statoTag(tag.lastSeen, tag.flags);
    final distanza = BleUtils.distanzaStringa(tag.rssi);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: Text(
          pecora['nome'] as String,
          style: const TextStyle(color: Color(0xFF2DFF6E)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2DFF6E)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF2DFF6E)),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssociaScreen(
                    tagId: tag.tagId,
                    tagIdHex: tag.tagIdHex,
                    nomeIniziale: pecora['nome'] as String?,
                    rfidIniziale: pecora['rfid'] as String?,
                    noteIniziale: pecora['note'] as String?,
                  ),
                ),
              );
              if (result == true && mounted) Navigator.pop(context, true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _elimina,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stato generale ──────────────────────────
            Card(
              color: const Color(0xFF0F2318),
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
                        _infoTile(stato.emoji, stato.label, 'Stato'),
                        _infoTile('📶', distanza, '${tag.rssi} dBm'),
                        _infoTile(
                          tag.isBatCritical ? '🪫' : '🔋',
                          '${tag.batteryPct}%',
                          '${tag.batteryMv} mV',
                        ),
                        _infoTile(
                          tag.isColdCritical ? '🥶' : '🌡️',
                          '${tag.temperature}°C',
                          'Temp',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Debug ────────────────────────────────────
            Card(
              color: const Color(0xFF0F2318),
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
                    _debugRow('TAG ID', tag.tagIdHex),
                    _debugRow('Tipo', tag.type == 0 ? 'Slave' : 'Master'),
                    _debugRow('Boot count', '${tag.bootCount}'),
                    _debugRow('RX count', '${tag.rxCount}'),
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
                    if (pecora['rfid'] != null)
                      _debugRow('RFID', pecora['rfid'] as String),
                    if (pecora['note'] != null)
                      _debugRow('Note', pecora['note'] as String),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Storico ──────────────────────────────────
            Card(
              color: const Color(0xFF0F2318),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'STORICO (7gg)',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          '${_storico.length} trasmissioni',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2DFF6E),
                        ),
                      )
                    else if (_storico.isEmpty)
                      const Text(
                        'Nessuna trasmissione registrata',
                        style: TextStyle(color: Colors.white38),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _storico.length > 50 ? 50 : _storico.length,
                        itemBuilder: (context, index) {
                          final s = _storico[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDateTime(s['timestamp'] as String),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '🔋${s['battery_pct']}%  '
                                  '🌡️${s['temperature']}°C  '
                                  '📶${s['rssi']}dBm',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
            fontSize: 14,
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

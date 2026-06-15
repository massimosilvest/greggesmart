import 'package:flutter/material.dart';
import '../models/tag_device.dart';
import '../services/database_service.dart';
import '../utils/ble_utils.dart';

class DettaglioMasterScreen extends StatefulWidget {
  final TagDevice tag;
  final Map<String, dynamic>? master;

  const DettaglioMasterScreen({super.key, required this.tag, this.master});

  @override
  State<DettaglioMasterScreen> createState() => _DettaglioMasterScreenState();
}

class _DettaglioMasterScreenState extends State<DettaglioMasterScreen> {
  final _db = DatabaseService();
  late TextEditingController _nomeController;
  late TextEditingController _rfidController;
  late TextEditingController _noteController;
  bool _saving = false;
  bool _modificaAperta = false;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(
      text: widget.master?['nome'] as String? ?? '',
    );
    _rfidController = TextEditingController(
      text: widget.master?['rfid'] as String? ?? '',
    );
    _noteController = TextEditingController(
      text: widget.master?['note'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _rfidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    print('DEBUG: inizio salvataggio');
    if (_nomeController.text.trim().isEmpty) {
      setState(() => _modificaAperta = false);
      return;
    }
    setState(() => _saving = true);

    try {
      print('DEBUG: chiamo salvaMaster');
      await _db.salvaMaster(
        tagId: widget.tag.tagId,
        nome: _nomeController.text.trim(),
        rfid: _rfidController.text.trim().isEmpty
            ? null
            : _rfidController.text.trim(),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      print('DEBUG: salvaMaster completato');
    } catch (e) {
      print('DEBUG: errore salvaMaster: $e');
      setState(() => _saving = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _modificaAperta = false;
    });
    Navigator.pop(context, true);
  }

  Future<void> _elimina() async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1F3D),
        title: const Text(
          'Elimina Master',
          style: TextStyle(color: Color(0xFF2D9BFF)),
        ),
        content: const Text(
          'Vuoi eliminare questo master dal registro?\n'
          'Verranno cancellati anche tutti i dati storici associati.',
          style: TextStyle(color: Colors.white70),
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
      await _db.eliminaMaster(widget.tag.tagId);
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    final distanza = BleUtils.distanzaStringa(tag.rssi);
    final stato = BleUtils.statoMaster(tag.lastSeen);
    final associato = widget.master != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1F3D),
        title: Text(
          widget.master?['nome'] as String? ?? 'Master ${tag.tagIdHex}',
          style: const TextStyle(color: Color(0xFF2D9BFF)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2D9BFF)),
        actions: [
          if (associato)
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
                          tag.gatewayMode ? '🔵' : stato.emoji,
                          tag.gatewayMode ? 'Gateway' : stato.label,
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

            // ── Associazione ─────────────────────────────
            Card(
              color: const Color(0xFF0F1F3D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ASSOCIAZIONE',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 1.5,
                          ),
                        ),
                        if (!_modificaAperta)
                          TextButton(
                            onPressed: () =>
                                setState(() => _modificaAperta = true),
                            child: Text(
                              associato ? 'MODIFICA' : 'ASSOCIA',
                              style: const TextStyle(
                                color: Color(0xFF2D9BFF),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!_modificaAperta && associato) ...[
                      _debugRow(
                        'Nome',
                        widget.master?['nome'] as String? ?? '-',
                      ),
                      if (widget.master?['rfid'] != null)
                        _debugRow('RFID', widget.master!['rfid'] as String),
                      if (widget.master?['note'] != null)
                        _debugRow('Note', widget.master!['note'] as String),
                    ],
                    if (!_modificaAperta && !associato)
                      const Text(
                        'Master non ancora nominato',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    if (_modificaAperta) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nomeController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Nome master (es. Master A)...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF0A1A2F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D9BFF),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D9BFF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _rfidController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'RFID (opzionale)...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF0A1A2F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D9BFF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Note (opzionale)...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF0A1A2F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D9BFF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saving ? null : _salva,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D9BFF),
                                foregroundColor: Colors.white,
                              ),
                              child: _saving
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text('SALVA'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _modificaAperta = false),
                            child: const Text(
                              'ANNULLA',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                        onPressed: null,
                        icon: const Icon(Icons.download),
                        label: const Text('ATTIVA GATEWAY E SCARICA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D9BFF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFF2D9BFF,
                          ).withValues(alpha: 0.3),
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

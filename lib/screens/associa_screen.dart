import 'package:flutter/material.dart';
import '../services/database_service.dart';

class AssociaScreen extends StatefulWidget {
  final int tagId;
  final String tagIdHex;
  final String? nomeIniziale;
  final String? rfidIniziale;
  final String? noteIniziale;

  const AssociaScreen({
    super.key,
    required this.tagId,
    required this.tagIdHex,
    this.nomeIniziale,
    this.rfidIniziale,
    this.noteIniziale,
  });

  @override
  State<AssociaScreen> createState() => _AssociaScreenState();
}

class _AssociaScreenState extends State<AssociaScreen> {
  late final TextEditingController _nomeController;
  late final TextEditingController _rfidController;
  late final TextEditingController _noteController;
  final _db = DatabaseService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.nomeIniziale ?? '');
    _rfidController = TextEditingController(text: widget.rfidIniziale ?? '');
    _noteController = TextEditingController(text: widget.noteIniziale ?? '');
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _rfidController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    if (_nomeController.text.trim().isEmpty) return;
    setState(() => _saving = true);

    await _db.salvaPecora(
      tagId: widget.tagId,
      nome: _nomeController.text.trim(),
      rfid: _rfidController.text.trim().isEmpty
          ? null
          : _rfidController.text.trim(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _elimina() async {
    // Chiedi conferma prima di eliminare
    final conferma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Elimina TAG',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        content: Text(
          'Vuoi eliminare "${widget.nomeIniziale ?? widget.tagIdHex}"?\nVerranno cancellati anche tutti i dati storici.',
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

    if (conferma == true) {
      await _db.eliminaPecora(widget.tagId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  bool get _isModifica => widget.nomeIniziale != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: Text(
          _isModifica
              ? 'Modifica ${widget.nomeIniziale}'
              : 'Associa ${widget.tagIdHex}',
          style: const TextStyle(color: Color(0xFF2DFF6E)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2DFF6E)),
        actions: [
          if (_isModifica)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _elimina,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nome pecora', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            TextField(
              controller: _nomeController,
              autofocus: !_isModifica,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'es. Bianca, 042, IT001...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F2318),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2DFF6E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2DFF6E)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'RFID (opzionale)',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rfidController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Codice RFID...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F2318),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2DFF6E)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Note (opzionale)',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Note...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F2318),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2DFF6E)),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _salva,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2DFF6E),
                  foregroundColor: Colors.black,
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        _isModifica ? 'AGGIORNA' : 'SALVA',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

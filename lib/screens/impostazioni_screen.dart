import 'package:flutter/material.dart';
import '../services/database_service.dart';

class ImpostazioniScreen extends StatefulWidget {
  const ImpostazioniScreen({super.key});

  @override
  State<ImpostazioniScreen> createState() => _ImpostazioniScreenState();
}

class _ImpostazioniScreenState extends State<ImpostazioniScreen> {
  final _db = DatabaseService();
  int _numeroMaster = 0;
  int _numeroMasterIniziale = 0;
  bool _loading = true;
  bool _salvato = false;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final config = await _db.getConfigurazione('numero_master');
    setState(() {
      _numeroMaster = int.tryParse(config ?? '0') ?? 0;
      _numeroMasterIniziale = _numeroMaster;
      _loading = false;
    });
  }

  Future<void> _salva() async {
    if (_numeroMaster != _numeroMasterIniziale) {
      final conferma = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F2318),
          title: const Text(
            'Attenzione',
            style: TextStyle(color: Color(0xFFFFB703)),
          ),
          content: const Text(
            'Cambiare il numero di master può rendere incoerenti i dati già scaricati.\n\nSalva prima un backup o verifica lo storico prima di procedere.',
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
              child: const Text(
                'CONTINUA',
                style: TextStyle(color: Color(0xFF2DFF6E)),
              ),
            ),
          ],
        ),
      );

      if (conferma != true) return;
    }

    await _db.salvaConfigurazione('numero_master', _numeroMaster.toString());
    _numeroMasterIniziale = _numeroMaster;
    setState(() => _salvato = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _salvato = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Impostazioni',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2DFF6E)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2DFF6E)),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONFIGURAZIONE MASTER',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Numero esatto di master nel gregge. Serve per verificare la sincronizzazione completa prima del download.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 32),

                  Center(
                    child: Text(
                      '$_numeroMaster',
                      style: const TextStyle(
                        color: Color(0xFF2DFF6E),
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      _numeroMaster == 0
                          ? 'Nessun master — solo smartphone'
                          : _numeroMaster == 1
                          ? '1 master'
                          : '$_numeroMaster master',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Slider(
                    value: _numeroMaster.toDouble(),
                    min: 0,
                    max: 15,
                    divisions: 15,
                    activeColor: const Color(0xFF2DFF6E),
                    inactiveColor: Colors.white12,
                    label: '$_numeroMaster',
                    onChanged: (value) {
                      setState(() => _numeroMaster = value.round());
                    },
                  ),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      Text(
                        '15',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _salva,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _salvato
                            ? Colors.green
                            : const Color(0xFF2DFF6E),
                        foregroundColor: Colors.black,
                      ),
                      child: Text(
                        _salvato ? 'SALVATO ✓' : 'SALVA',
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

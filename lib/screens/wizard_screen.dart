import 'package:flutter/material.dart';
import '../services/database_service.dart';

class WizardScreen extends StatefulWidget {
  const WizardScreen({super.key});

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

class _WizardScreenState extends State<WizardScreen> {
  final _db = DatabaseService();
  int _numeroMaster = 0;

  Future<void> _salva() async {
    await _db.salvaNumeroMaster(_numeroMaster);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Configurazione Gregge',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.settings, color: Color(0xFF2DFF6E), size: 48),
              const SizedBox(height: 24),
              const Text(
                'Benvenuto in Gregge Smart!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Quanti master reali hai nel gregge?',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Con master = 0 non cambia nulla (solo smartphone). Con master >= 1 il sistema usa sempre 1 gateway dedicato e permanente, oltre ai master reali. Potrai modificare questa configurazione in qualsiasi momento dalle impostazioni.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const Spacer(),

              // Numero grande al centro
              Center(
                child: Text(
                  '$_numeroMaster',
                  style: const TextStyle(
                    color: Color(0xFF2DFF6E),
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Center(
                child: Text(
                  _numeroMaster == 0
                      ? 'Nessun master — solo smartphone'
                      : _numeroMaster == 1
                      ? '1 master + 1 gateway (obbligatorio)'
                      : '$_numeroMaster master + 1 gateway (obbligatorio)',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),

              // Slider per selezionare 0-15
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

              const SizedBox(height: 8),
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

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _salva,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2DFF6E),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text(
                    'CONFERMA',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

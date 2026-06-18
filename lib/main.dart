import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';
import 'screens/wizard_screen.dart';
import 'services/database_service.dart';

void main() {
  runApp(const GreggeSmartApp());
}

class GreggeSmartApp extends StatelessWidget {
  const GreggeSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gregge Smart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2DFF6E),
          surface: Color(0xFF0F2318),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A1A0F),
        useMaterial3: true,
      ),
      home: const PermissionWrapper(),
    );
  }
}

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _granted = false;
  bool _configurazioneCompletata = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _inizializza();
  }

  Future<void> _inizializza() async {
    // Richiedi permessi
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // Controlla se il wizard è già stato completato
    final db = DatabaseService();
    final config = await db.getConfigurazione('numero_master');

    setState(() {
      _granted = true;
      _configurazioneCompletata = config != null;
      _loading = false;
    });
  }

  Future<void> _apriWizard() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WizardScreen()),
    );
    if (result == true) {
      setState(() => _configurazioneCompletata = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2DFF6E)),
        ),
      );
    }

    if (!_granted) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2DFF6E)),
        ),
      );
    }

    if (!_configurazioneCompletata) {
      // Mostra wizard al primo avvio
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _apriWizard();
      });
    }

    return const HomeScreen();
  }
}

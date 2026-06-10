import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_scanner.dart';
import '../services/database_service.dart';
import '../models/tag_device.dart';
import '../widgets/tag_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BleScanner _scanner = BleScanner();
  final DatabaseService _db = DatabaseService();
  Map<int, TagDevice> _tags = {};
  Map<int, Map<String, dynamic>> _pecore = {};
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _scanner.tagsStream.listen((tags) {
      setState(() => _tags = tags);
      _aggiornaPecore(tags.keys.toList());
    });
    _requestAndScan();
  }

  Future<void> _aggiornaPecore(List<int> tagIds) async {
    for (final tagId in tagIds) {
      if (!_pecore.containsKey(tagId)) {
        final pecora = await _db.getPecora(tagId);
        if (pecora != null) {
          setState(() => _pecore[tagId] = pecora);
        }
      }
    }
  }

  Future<void> _ricaricaPecore() async {
    final nuovePecore = <int, Map<String, dynamic>>{};
    for (final tagId in _tags.keys) {
      final pecora = await _db.getPecora(tagId);
      if (pecora != null) {
        nuovePecore[tagId] = pecora;
      }
    }
    setState(() => _pecore = nuovePecore);
  }

  Future<void> _requestAndScan() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    _startScan();
  }

  void _startScan() {
    setState(() => _isScanning = true);
    _scanner.startScan();
  }

  void _stopScan() {
    setState(() => _isScanning = false);
    _scanner.stopScan();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Gregge Smart',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop : Icons.play_arrow,
              color: const Color(0xFF2DFF6E),
            ),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: _tags.isEmpty
          ? const Center(
              child: Text(
                'Nessun TAG rilevato...',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: _tags.length,
              itemBuilder: (context, index) {
                final tag = _tags.values.elementAt(index);
                return TagCard(
                  tag: tag,
                  pecora: _pecore[tag.tagId],
                  onAggiornato: _ricaricaPecore,
                );
              },
            ),
    );
  }
}

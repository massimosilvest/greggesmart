import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_scanner.dart';
import '../services/database_service.dart';
import '../models/tag_device.dart';
import '../widgets/tag_card.dart';
import 'associa_screen.dart';

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
  Map<int, Map<String, dynamic>> _master = {};
  bool _isScanning = false;
  bool _bluetoothOn = true;

  @override
  void initState() {
    super.initState();

    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _bluetoothOn = state == BluetoothAdapterState.on;
      });
      if (!_bluetoothOn && _isScanning) {
        setState(() => _isScanning = false);
        _scanner.stopScan();
      }
    });

    _scanner.tagsStream.listen((tags) {
      setState(() => _tags = tags);
      _aggiornaDati(tags.keys.toList());
    });

    _caricaTuttiDati();
    _requestAndScan();
  }

  Future<void> _caricaTuttiDati() async {
    await _caricaPecoreAssociate();
    await _caricaMasterAssociati();
  }

  Future<void> _caricaPecoreAssociate() async {
    final pecore = await _db.getPecore();
    final mappa = <int, Map<String, dynamic>>{};
    for (final p in pecore) {
      mappa[p['tag_id'] as int] = p;
    }
    setState(() => _pecore = mappa);
  }

  Future<void> _caricaMasterAssociati() async {
    final master = await _db.getMaster();
    final mappa = <int, Map<String, dynamic>>{};
    for (final m in master) {
      mappa[m['tag_id'] as int] = m;
    }
    setState(() => _master = mappa);
  }

  Future<void> _aggiornaDati(List<int> tagIds) async {
    for (final tagId in tagIds) {
      final tag = _tags[tagId];
      if (tag == null) continue;

      if (tag.isMaster) {
        if (!_master.containsKey(tagId)) {
          final m = await _db.getSingoloMaster(tagId);
          if (m != null) setState(() => _master[tagId] = m);
        }
      } else {
        if (!_pecore.containsKey(tagId)) {
          final p = await _db.getPecora(tagId);
          if (p != null) setState(() => _pecore[tagId] = p);
        }
      }
    }
  }

  Future<void> _ricaricaDati() async {
    await _caricaTuttiDati();
  }

  Future<void> _requestAndScan() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) {
      _startScan();
    }
  }

  void _startScan() {
    if (!_bluetoothOn) {
      _mostraAlertBluetooth();
      return;
    }
    setState(() => _isScanning = true);
    _scanner.startScan();
  }

  void _stopScan() {
    setState(() => _isScanning = false);
    _scanner.stopScan();
  }

  void _mostraAlertBluetooth() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Bluetooth spento',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        content: const Text(
          'Attiva il Bluetooth per scansionare i TAG.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FlutterBluePlus.turnOn();
            },
            child: const Text(
              'ATTIVA',
              style: TextStyle(color: Color(0xFF2DFF6E)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ANNULLA',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  List<_TagEntry> _buildLista() {
    final lista = <_TagEntry>[];

    // TAG visti dalla scansione
    for (final tag in _tags.values) {
      if (tag.isMaster) {
        lista.add(
          _TagEntry(tag: tag, pecora: null, master: _master[tag.tagId]),
        );
      } else {
        lista.add(
          _TagEntry(tag: tag, pecora: _pecore[tag.tagId], master: null),
        );
      }
    }

    // Pecore associate ma non viste
    for (final entry in _pecore.entries) {
      if (!_tags.containsKey(entry.key)) {
        lista.add(_TagEntry(tag: null, pecora: entry.value, master: null));
      }
    }

    // Master associati ma non visti
    for (final entry in _master.entries) {
      if (!_tags.containsKey(entry.key)) {
        lista.add(_TagEntry(tag: null, pecora: null, master: entry.value));
      }
    }

    // Ordina: master prima, poi slave per stato
    lista.sort((a, b) {
      // Master sempre in cima
      final aMaster = a.tag?.isMaster ?? (a.master != null);
      final bMaster = b.tag?.isMaster ?? (b.master != null);
      if (aMaster && !bMaster) return -1;
      if (!aMaster && bMaster) return 1;
      return b.statoOrdine.compareTo(a.statoOrdine);
    });

    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final lista = _buildLista();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Gregge Smart',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        actions: [
          Icon(
            _bluetoothOn ? Icons.bluetooth : Icons.bluetooth_disabled,
            color: _bluetoothOn ? const Color(0xFF2DFF6E) : Colors.red,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop : Icons.play_arrow,
              color: const Color(0xFF2DFF6E),
            ),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: lista.isEmpty
          ? const Center(
              child: Text(
                'Nessun TAG rilevato...',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: lista.length,
              itemBuilder: (context, index) {
                final entry = lista[index];

                // TAG vivo dalla scansione
                if (entry.tag != null) {
                  return TagCard(
                    tag: entry.tag!,
                    pecora: entry.pecora,
                    master: entry.master,
                    onAggiornato: _ricaricaDati,
                  );
                }

                // Pecora associata ma non vista
                if (entry.pecora != null) {
                  return _CardAssenteSlave(
                    pecora: entry.pecora!,
                    onAggiornato: _ricaricaDati,
                  );
                }

                // Master associato ma non visto
                if (entry.master != null) {
                  return _CardAssenteMaster(
                    master: entry.master!,
                    onAggiornato: _ricaricaDati,
                  );
                }

                return const SizedBox.shrink();
              },
            ),
    );
  }
}

// ── Entry combinata ──────────────────────────────────
class _TagEntry {
  final TagDevice? tag;
  final Map<String, dynamic>? pecora;
  final Map<String, dynamic>? master;

  _TagEntry({required this.tag, required this.pecora, required this.master});

  int get statoOrdine {
    if (tag == null) return 3;
    final secondi = DateTime.now().difference(tag!.lastSeen).inSeconds;
    if (secondi < 60) return 0;
    if (secondi < 120) return 1;
    if (secondi < 300) return 2;
    return 3;
  }
}

// ── Card pecora assente ──────────────────────────────
class _CardAssenteSlave extends StatelessWidget {
  final Map<String, dynamic> pecora;
  final VoidCallback onAggiornato;

  const _CardAssenteSlave({required this.pecora, required this.onAggiornato});

  Future<void> _apriModifica(BuildContext context) async {
    final tagId = pecora['tag_id'] as int;
    final tagIdHex =
        '0x${tagId.toRadixString(16).toUpperCase().padLeft(4, '0')}';
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssociaScreen(
          tagId: tagId,
          tagIdHex: tagIdHex,
          nomeIniziale: pecora['nome'] as String?,
          rfidIniziale: pecora['rfid'] as String?,
          noteIniziale: pecora['note'] as String?,
        ),
      ),
    );
    if (result == true) onAggiornato();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _apriModifica(context),
      child: Card(
        color: const Color(0xFF0F2318),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text('⬛', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pecora['nome'] as String,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'Non vista',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card master assente ──────────────────────────────
class _CardAssenteMaster extends StatelessWidget {
  final Map<String, dynamic> master;
  final VoidCallback onAggiornato;

  const _CardAssenteMaster({required this.master, required this.onAggiornato});

  @override
  Widget build(BuildContext context) {
    final nome =
        master['nome'] as String? ??
        '0x${(master['tag_id'] as int).toRadixString(16).toUpperCase().padLeft(4, '0')}';

    return Card(
      color: const Color(0xFF0F1F3D),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.hub, color: Colors.white38, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nome,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Text(
              'Non visto',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_scanner.dart';
import '../services/database_service.dart';
import '../models/tag_device.dart';
import '../widgets/tag_card.dart';
import '../utils/ble_utils.dart';
import 'associa_screen.dart';
import 'dettaglio_master_screen.dart';
import 'impostazioni_screen.dart';

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
  Map<int, int> _slaveMasterByDb = {};
  bool _isScanning = false;
  bool _bluetoothOn = true;
  Timer? _refreshTimer;
  int _numeroMaster = 0;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();

    FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        _bluetoothOn = state == BluetoothAdapterState.on;
      });
      if (!_bluetoothOn && _isScanning) {
        setState(() => _isScanning = false);
        _scanner.stopScan();
      }
    });

    _scanner.tagsStream.listen((tags) {
      if (!mounted) return;
      setState(() => _tags = tags);
      _aggiornaDati(tags.keys.toList());
    });

    _caricaTuttiDati();
    _requestAndScan();

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _caricaTuttiDati() async {
    final numeroMaster = await _db.getNumeroMaster();

    final pecore = await _db.getPecore();
    final mapPecore = <int, Map<String, dynamic>>{};
    for (final p in pecore) {
      mapPecore[p['tag_id'] as int] = p;
    }

    final master = await _db.getMaster();
    final mapMaster = <int, Map<String, dynamic>>{};
    for (final m in master) {
      mapMaster[m['tag_id'] as int] = m;
    }

    final slaveMasterByDb = await _db.getUltimoMasterPerSlave();

    if (!mounted) return;
    setState(() {
      _numeroMaster = numeroMaster;
      _pecore = mapPecore;
      _master = mapMaster;
      _slaveMasterByDb = slaveMasterByDb;
    });
  }

  Future<void> _aggiornaDati(List<int> tagIds) async {
    for (final tagId in tagIds) {
      final tag = _tags[tagId];
      if (tag == null) continue;

      if (tag.isMaster) {
        final m = await _db.getSingoloMaster(tagId);
        if (m != null && mounted) setState(() => _master[tagId] = m);
      } else {
        final p = await _db.getPecora(tagId);
        if (p != null && mounted) setState(() => _pecore[tagId] = p);
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
    if (state == BluetoothAdapterState.on) _startScan();
  }

  void _startScan() {
    if (!_bluetoothOn) {
      _mostraAlertBluetooth();
      return;
    }
    setState(() => _isScanning = true);
    _scanner.startScan();
  }

  void _pausaScanPerGateway() {
    _scanner.stopScan();
  }

  void _riprendiScanDopoGateway() {
    if (_isScanning) {
      _scanner.startScan();
    }
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
    _refreshTimer?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  List<int> _masterIdsDaMostrare() {
    final ids = <int>[];

    for (final id in _master.keys) {
      if (!ids.contains(id)) ids.add(id);
    }

    for (final tag in _tags.values) {
      if (tag.isMaster && !ids.contains(tag.tagId)) {
        ids.add(tag.tagId);
      }
    }

    if (_numeroMaster > 0) {
      for (final id in _slaveMasterByDb.values) {
        if (!ids.contains(id)) ids.add(id);
      }
    }

    return ids;
  }

  List<int> _slaveIdsSenzaMaster() {
    final ids = <int>{};

    for (final tag in _tags.values) {
      if (tag.isSlave) ids.add(tag.tagId);
    }

    ids.addAll(_pecore.keys);
    ids.removeWhere(_slaveMasterByDb.containsKey);

    final result = ids.toList();
    result.sort();
    return result;
  }

  Widget _buildSlaveTile(int slaveId, {required bool nested}) {
    final tag = _tags[slaveId];
    final pecora = _pecore[slaveId];

    Widget content;

    if (tag != null) {
      content = TagCard(
        tag: tag,
        pecora: pecora,
        master: null,
        onAggiornato: _ricaricaDati,
        onPausaScan: _pausaScanPerGateway,
        onRiprendiScan: _riprendiScanDopoGateway,
      );
    } else if (pecora != null) {
      content = _CardAssenteSlave(pecora: pecora, onAggiornato: _ricaricaDati);
    } else {
      content = const SizedBox.shrink();
    }

    if (!nested) return content;
    return Padding(padding: const EdgeInsets.only(left: 16), child: content);
  }

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

  Widget _buildMasterTile(int masterId) {
    final tag = _tags[masterId];
    final master = _master[masterId] ?? {'tag_id': masterId};

    if (tag != null) {
      return TagCard(
        tag: tag,
        pecora: null,
        master: _master[masterId],
        onAggiornato: _ricaricaDati,
        onPausaScan: _pausaScanPerGateway,
        onRiprendiScan: _riprendiScanDopoGateway,
      );
    }

    return _CardAssenteMaster(master: master, onAggiornato: _ricaricaDati);
  }

  List<TagDevice> _liveTagsOrdinati() {
    final tags = _tags.values.toList();
    tags.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return tags;
  }

  int _numeroSlaveAssociati(int masterId) {
    return _slaveMasterByDb.values.where((id) => id == masterId).length;
  }

  Widget _buildLiveTab() {
    final tags = _liveTagsOrdinati();

    final children = <Widget>[
      const _SectionHeader(
        title: 'LIVE BLE',
        subtitle: 'Segnali in tempo reale, senza logica ad albero',
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Qui vedi tutto quello che l\'antenna riceve ora: è la vista utile per cercare una pecora nel gregge.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
    ];

    if (tags.isEmpty) {
      children.add(
        const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 48),
            child: Text(
              'Nessun TAG in live...',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    } else {
      for (final tag in tags) {
        children.add(
          TagCard(
            tag: tag,
            pecora: _pecore[tag.tagId],
            master: _master[tag.tagId],
            onAggiornato: _ricaricaDati,
            onPausaScan: _pausaScanPerGateway,
            onRiprendiScan: _riprendiScanDopoGateway,
          ),
        );
      }
    }

    return ListView(children: children);
  }

  Widget _buildTreeTab() {
    final children = <Widget>[];
    final modalitaIbrida = _numeroMaster > 0;

    if (modalitaIbrida) {
      final masterIds = _masterIdsDaMostrare();
      if (masterIds.isNotEmpty) {
        children.add(
          const _SectionHeader(
            title: 'ALBERO DATABASE',
            subtitle: 'Relazione ricostruita dopo il download dal master',
          ),
        );
        for (final masterId in masterIds) {
          children.add(_buildMasterTile(masterId));

          final slaveIds =
              _slaveMasterByDb.entries
                  .where((entry) => entry.value == masterId)
                  .map((entry) => entry.key)
                  .toList()
                ..sort();

          if (slaveIds.isNotEmpty) {
            children.add(
              const Padding(
                padding: EdgeInsets.only(left: 28, top: 4, bottom: 2),
                child: Text(
                  'Slave associati',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            );
            for (final slaveId in slaveIds) {
              children.add(_buildSlaveTile(slaveId, nested: true));
            }
          }

          children.add(const SizedBox(height: 6));
        }
      }

      final slavesSenzaMaster = _slaveIdsSenzaMaster();
      if (slavesSenzaMaster.isNotEmpty) {
        children.add(
          const _SectionHeader(
            title: 'TELEFONO / NON ASSEGNATI',
            subtitle: 'Slave presenti nel database ma non agganciati',
          ),
        );
        for (final slaveId in slavesSenzaMaster) {
          children.add(_buildSlaveTile(slaveId, nested: false));
        }
      }
    } else {
      final slaves = _slaveIdsSenzaMaster();
      if (slaves.isNotEmpty) {
        children.add(
          const _SectionHeader(
            title: 'GATEWAY / TELEFONO',
            subtitle: 'Modalità senza master: il telefono è il root operativo',
          ),
        );
        for (final slaveId in slaves) {
          children.add(_buildSlaveTile(slaveId, nested: false));
        }
      }
    }

    if (children.isEmpty) {
      children.add(
        const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 48),
            child: Text(
              'Nessun dato nel database...',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    }

    return ListView(children: children);
  }

  Widget _buildMapTile(TagDevice tag) {
    final nome = _master[tag.tagId]?['nome'] as String? ?? tag.tagIdHex;
    final distanza = BleUtils.distanzaStringa(tag.rssi);
    final stato = BleUtils.statoMaster(tag.lastSeen);
    final slaveCount = _numeroSlaveAssociati(tag.tagId);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DettaglioMasterScreen(
              tag: tag,
              master: _master[tag.tagId],
              onPausaScan: _pausaScanPerGateway,
              onRiprendiScan: _riprendiScanDopoGateway,
              onAggiornato: _ricaricaDati,
            ),
          ),
        );
        if (result == true) _ricaricaDati();
      },
      child: Card(
        color: const Color(0xFF0F1F3D),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Column(
                children: [
                  Icon(
                    tag.gatewayMode ? Icons.place : Icons.hub,
                    color: tag.gatewayMode ? Colors.amber : stato.color,
                    size: 28,
                  ),
                  Text(stato.emoji, style: const TextStyle(fontSize: 10)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        color: stato.color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      tag.gpsValid
                          ? 'GPS: ${tag.latitude?.toStringAsFixed(4)}, ${tag.longitude?.toStringAsFixed(4)}'
                          : 'GPS: no fix',
                      style: TextStyle(
                        color: tag.gpsValid ? Colors.white54 : Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Slave agganciati: $slaveCount',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _batteryIcon(tag),
                  const SizedBox(height: 4),
                  Text(
                    distanza,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
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

  Widget _buildMapTab() {
    final masters = _tags.values.where((tag) => tag.isMaster).toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

    final children = <Widget>[
      const _SectionHeader(
        title: 'MAPPA GPS',
        subtitle:
            'Vista semplificata dei master con posizione e numero di slave',
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Qui teniamo i soli master come riferimento geografico. Più avanti potremo sostituire questa vista con una mappa vera.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
    ];

    if (masters.isEmpty) {
      children.add(
        const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 48),
            child: Text(
              'Nessun master live con GPS...',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    } else {
      for (final tag in masters) {
        children.add(_buildMapTile(tag));
      }
    }

    return ListView(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final tabTitles = ['Live BLE', 'Albero', 'Mappa'];
    final tabIcons = [Icons.radar, Icons.account_tree, Icons.map];

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: Text(
          tabTitles[_selectedTabIndex],
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        actions: [
          Icon(
            _bluetoothOn ? Icons.bluetooth : Icons.bluetooth_disabled,
            color: _bluetoothOn ? const Color(0xFF2DFF6E) : Colors.red,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF2DFF6E)),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImpostazioniScreen()),
              );
              _ricaricaDati();
            },
          ),
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop : Icons.play_arrow,
              color: const Color(0xFF2DFF6E),
            ),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [_buildLiveTab(), _buildTreeTab(), _buildMapTab()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) => setState(() => _selectedTabIndex = index),
        backgroundColor: const Color(0xFF0F2318),
        selectedItemColor: const Color(0xFF2DFF6E),
        unselectedItemColor: Colors.white54,
        items: List.generate(
          tabTitles.length,
          (index) => BottomNavigationBarItem(
            icon: Icon(tabIcons[index]),
            label: tabTitles[index],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF2DFF6E),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

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

class _CardAssenteMaster extends StatelessWidget {
  final Map<String, dynamic> master;
  final VoidCallback onAggiornato;

  const _CardAssenteMaster({required this.master, required this.onAggiornato});

  @override
  Widget build(BuildContext context) {
    final tagId = master['tag_id'] as int;
    final nome =
        master['nome'] as String? ??
        '0x${tagId.toRadixString(16).toUpperCase().padLeft(4, '0')}';
    final stato = BleUtils.statoMaster(null);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DettaglioMasterScreen(
              tag: TagDevice(
                tagId: tagId,
                type: 1,
                batteryPct: 0,
                batteryMv: 0,
                flags: 0,
                bootCount: 0,
                temperature: 0,
                lastSeen: DateTime(2000),
                rssi: -999,
              ),
              master: master,
              onPausaScan:
                  () {}, // Funzione vuota: non blocca la scansione generale
              onRiprendiScan:
                  () {}, // Funzione vuota: nessun effetto sulla scansione
              onAggiornato: onAggiornato,
            ),
          ),
        );
        if (result == true) onAggiornato();
      },
      child: Card(
        color: const Color(0xFF0F1F3D),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Column(
                children: [
                  Icon(Icons.hub, color: stato.color, size: 28),
                  Text(stato.emoji, style: const TextStyle(fontSize: 10)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nome,
                  style: TextStyle(
                    color: stato.color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                stato.label,
                style: TextStyle(color: stato.color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

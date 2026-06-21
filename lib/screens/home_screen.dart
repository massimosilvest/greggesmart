import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_scanner.dart';
import '../services/database_service.dart';
import '../services/gateway_service.dart';
import '../models/tag_device.dart';
import '../widgets/tag_card.dart';
import '../utils/ble_utils.dart';
import 'associa_screen.dart';
import 'database_viewer_screen.dart';
import 'dettaglio_master_screen.dart';
import 'impostazioni_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _phonePositionSub;
  bool _mappaInizializzata = false;
  bool _mapReady = false;
  bool _centroInizialeRisolto = false;
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
  int _dataModeIndex = 0;
  int _mapModeIndex = 0;
  DateTime _giornoStorico = DateTime.now();
  bool _storicoLoading = false;
  List<Map<String, dynamic>> _storicoPunti = [];
  int? _storicoTagFilter;
  bool _downloadInProgress = false;
  Timer? _downloadTimeout;
  int? _ultimoAvvisoMismatchMaster;

  static const String _cfgPhoneLat = 'last_phone_lat';
  static const String _cfgPhoneLon = 'last_phone_lon';
  static const String _cfgMasterLat = 'last_master_lat';
  static const String _cfgMasterLon = 'last_master_lon';
  static const int _liveSlaveTimeoutSeconds = 120;

  @override
  void initState() {
    super.initState();
    _inizializzaCentroMappa();
    _avviaTrackingPosizionePastore();

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
      _aggiornaFallbackMasterDaLive(tags);
      _tryApplyInitialMapCenter();
      _aggiornaDati(tags.keys.toList());
      _arricchisciSlaveConGpsTelefonoSeNomade(tags);
      _valutaAvvisoNumeroMaster(tags);
    });

    _caricaTuttiDati();
    _caricaTracciaStorico();
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

  void _valutaAvvisoNumeroMaster(Map<int, TagDevice> tags) {
    final masterLiveCount = tags.values.where((tag) => tag.isMaster).length;

    if (masterLiveCount == _numeroMaster) {
      _ultimoAvvisoMismatchMaster = null;
      return;
    }

    if (_ultimoAvvisoMismatchMaster == masterLiveCount) return;
    _ultimoAvvisoMismatchMaster = masterLiveCount;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF0F2318),
          title: const Text(
            'Numero master non coerente',
            style: TextStyle(color: Color(0xFFFFB703)),
          ),
          content: Text(
            'Nel wizard hai impostato $_numeroMaster master, ma ora ne vedo $masterLiveCount in live.\n\nSe devi cambiare questo valore, salva prima i dati già presenti: la logica di scarico e il mapping dello storico possono diventare incoerenti.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'IGNORA',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ImpostazioniScreen()),
                );
              },
              child: const Text(
                'APRi IMPOSTAZIONI',
                style: TextStyle(color: Color(0xFF2DFF6E)),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _ricaricaDati() async {
    await _caricaTuttiDati();
    await _caricaTracciaStorico();
  }

  Future<void> _apriDettaglioMaster(TagDevice tag) async {
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
    _phonePositionSub?.cancel();
    _refreshTimer?.cancel();
    _downloadTimeout?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _avviaTrackingPosizionePastore() async {
    try {
      var permesso = await Geolocator.checkPermission();
      if (permesso == LocationPermission.denied) {
        permesso = await Geolocator.requestPermission();
      }

      final gpsConsentito =
          permesso == LocationPermission.always ||
          permesso == LocationPermission.whileInUse;
      if (!gpsConsentito) return;

      final servizioAttivo = await Geolocator.isLocationServiceEnabled();
      if (!servizioAttivo) return;

      await _phonePositionSub?.cancel();
      _phonePositionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((pos) {
            if (!mounted) return;
            final nuovaPos = LatLng(pos.latitude, pos.longitude);

            setState(() => _centroFallback = nuovaPos);
            unawaited(
              _salvaPosizioneConfig(
                keyLat: _cfgPhoneLat,
                keyLon: _cfgPhoneLon,
                pos: nuovaPos,
              ),
            );
          });
    } catch (e) {
      debugPrint('Errore tracking posizione pastore: $e');
    }
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

  Future<void> _arricchisciSlaveConGpsTelefonoSeNomade(
    Map<int, TagDevice> tags,
  ) async {
    if (_numeroMaster > 0) return;
    if (_centroFallback == null) return;

    for (final tag in tags.values) {
      if (!tag.isSlave) continue;

      await _db.salvaTrasmissione(
        tagId: tag.tagId,
        masterId: null,
        latitude: _centroFallback!.latitude,
        longitude: _centroFallback!.longitude,
        gpsValid: true,
        bootCount: tag.bootCount,
        batteryPct: tag.batteryPct,
        batteryMv: tag.batteryMv,
        temperature: tag.temperature,
        rssi: tag.rssi,
      );
    }
  }

  List<TagDevice> _liveTagsOrdinati() {
    final tags = _tags.values.toList();
    tags.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return tags;
  }

  int? _selezionaMasterMiglioreDaLive() {
    final masterLive = _tags.values.where((tag) => tag.isMaster).toList();
    if (masterLive.isEmpty) return null;

    masterLive.sort((a, b) => a.rssi.compareTo(b.rssi));
    return masterLive.last.tagId;
  }

  Future<void> _scaricaDaGatewayUnificato() async {
    if (_downloadInProgress) return;

    final masterId = _selezionaMasterMiglioreDaLive();
    if (masterId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun master live visibile'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final statusNotifier = ValueNotifier<String>('Avvio download...');
    var dialogAperto = false;

    void closeDialogIfOpen() {
      if (!dialogAperto || !mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
      dialogAperto = false;
    }

    setState(() {
      _downloadInProgress = true;
    });

    _pausaScanPerGateway();

    dialogAperto = true;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Download Gateway',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF2D9BFF)),
            const SizedBox(height: 16),
            ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (context, value, _) => Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );

    _downloadTimeout = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        closeDialogIfOpen();
        setState(() => _downloadInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download scaduto dopo 5 minuti'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });

    try {
      final gateway = GatewayService();
      final download = await gateway.scaricaDaGateway(
        masterId: masterId,
        expectedMasterCount: _numeroMaster > 0 ? _numeroMaster : 1,
        onStatus: (status) {
          if (!mounted) return;
          statusNotifier.value = status;
        },
      );

      if (!mounted) return;
      _downloadTimeout?.cancel();

      await _db.salvaDatiGateway(download.records);
      await _ricaricaDati();
      final slaveAssociati = _slaveMasterByDb.values
          .where((id) => id == masterId)
          .length;

      closeDialogIfOpen();

      if (mounted) {
        final resetInfo = download.clearSent
            ? 'Reset memoria inviato.'
            : 'Reset memoria NON inviato: dump da ${download.masterIdsInDump.length}/${download.expectedMasterCount} master.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              download.records.isEmpty
                  ? 'Download completato: 0 record (nessun nuovo dato). $resetInfo'
                  : 'Scaricati ${download.records.length} record. Slave ora associati a questo master: $slaveAssociati. $resetInfo',
            ),
            backgroundColor: download.records.isEmpty
                ? Colors.orange
                : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Errore download gateway: $e');
      if (mounted) {
        closeDialogIfOpen();
        _downloadTimeout?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      _downloadTimeout?.cancel();
      if (mounted) {
        closeDialogIfOpen();
        setState(() => _downloadInProgress = false);
      }
      _riprendiScanDopoGateway();
      statusNotifier.dispose();
    }
  }

  Widget _buildLiveTab() {
    final tags = _liveTagsOrdinati();
    final masterLiveCount = tags.where((tag) => tag.isMaster).length;
    final slaveLiveCount = tags.where((tag) => tag.isSlave).length;

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
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Totale live: master $masterLiveCount | slave $slaveLiveCount',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
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
    final slaveLiveCount = _numeroSlaveLivePerMaster(tag.tagId);

    return GestureDetector(
      onTap: () => _apriDettaglioMaster(tag),
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
                      'Slave live rilevati: $slaveLiveCount',
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

  List<TagDevice> _mastersConGps() {
    final masters = _tags.values
        .where(
          (tag) =>
              tag.isMaster &&
              tag.gpsValid &&
              tag.latitude != null &&
              tag.longitude != null,
        )
        .toList();
    masters.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return masters;
  }

  List<TagDevice> _slaveLive() {
    final now = DateTime.now();
    final slaves = _tags.values
        .where((tag) => tag.isSlave)
        .where(
          (tag) =>
              now.difference(tag.lastSeen).inSeconds <=
              _liveSlaveTimeoutSeconds,
        )
        .toList();
    slaves.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return slaves;
  }

  int _numeroSlaveLivePerMaster(int masterId) {
    final now = DateTime.now();
    var count = 0;

    for (final entry in _slaveMasterByDb.entries) {
      if (entry.value != masterId) continue;
      final slaveTag = _tags[entry.key];
      if (slaveTag == null || !slaveTag.isSlave) continue;

      final fresh =
          now.difference(slaveTag.lastSeen).inSeconds <=
          _liveSlaveTimeoutSeconds;
      if (fresh) count++;
    }

    return count;
  }

  DateTime _inizioGiorno(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _fineGiorno(DateTime date) {
    final inizio = _inizioGiorno(date);
    return inizio
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
  }

  Future<void> _caricaTracciaStorico() async {
    if (!mounted) return;
    setState(() => _storicoLoading = true);

    try {
      final from = _inizioGiorno(_giornoStorico);
      final to = _fineGiorno(_giornoStorico);
      final punti = await _db.getStoricoTracciaGps(from: from, to: to);

      if (!mounted) return;
      setState(() {
        _storicoPunti = punti;
        final idsDisponibili = _storicoTagDisponibili();
        if (_storicoTagFilter != null &&
            !idsDisponibili.contains(_storicoTagFilter)) {
          _storicoTagFilter = null;
        }
      });
    } catch (e) {
      debugPrint('Errore caricamento traccia storica: $e');
    } finally {
      if (mounted) {
        setState(() => _storicoLoading = false);
      }
    }
  }

  List<int> _storicoTagDisponibili() {
    final ids = <int>{};
    for (final row in _storicoPunti) {
      final id = row['tag_id'] as int?;
      if (id != null) ids.add(id);
    }
    final list = ids.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> _storicoPuntiFiltrati() {
    if (_storicoTagFilter == null) return _storicoPunti;
    return _storicoPunti
        .where((row) => row['tag_id'] == _storicoTagFilter)
        .toList();
  }

  Future<void> _scegliGiornoStorico() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _giornoStorico,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked == null || !mounted) return;
    setState(() => _giornoStorico = picked);
    await _caricaTracciaStorico();
  }

  LatLng? _centroFallback;
  LatLng? _centroMasterFallback;

  Future<LatLng?> _leggiPosizioneDaConfig(String keyLat, String keyLon) async {
    final latStr = await _db.getConfigurazione(keyLat);
    final lonStr = await _db.getConfigurazione(keyLon);
    final lat = double.tryParse(latStr ?? '');
    final lon = double.tryParse(lonStr ?? '');
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  Future<void> _salvaPosizioneConfig({
    required String keyLat,
    required String keyLon,
    required LatLng pos,
  }) async {
    await _db.salvaConfigurazione(keyLat, pos.latitude.toString());
    await _db.salvaConfigurazione(keyLon, pos.longitude.toString());
  }

  Future<void> _inizializzaCentroMappa() async {
    LatLng? posizioneTelefono;
    LatLng? posizioneMaster;

    try {
      var permesso = await Geolocator.checkPermission();
      if (permesso == LocationPermission.denied) {
        permesso = await Geolocator.requestPermission();
      }

      final gpsConsentito =
          permesso == LocationPermission.always ||
          permesso == LocationPermission.whileInUse;

      if (gpsConsentito) {
        final servizioAttivo = await Geolocator.isLocationServiceEnabled();
        if (servizioAttivo) {
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 6),
              ),
            );
            posizioneTelefono = LatLng(pos.latitude, pos.longitude);
          } catch (_) {
            final pos = await Geolocator.getLastKnownPosition();
            if (pos != null) {
              posizioneTelefono = LatLng(pos.latitude, pos.longitude);
            }
          }
        }
      }

      posizioneTelefono ??= await _leggiPosizioneDaConfig(
        _cfgPhoneLat,
        _cfgPhoneLon,
      );
      posizioneMaster = await _leggiPosizioneDaConfig(
        _cfgMasterLat,
        _cfgMasterLon,
      );

      if (posizioneTelefono != null) {
        await _salvaPosizioneConfig(
          keyLat: _cfgPhoneLat,
          keyLon: _cfgPhoneLon,
          pos: posizioneTelefono,
        );
      }
    } catch (e) {
      debugPrint('Errore inizializzazione centro mappa: $e');
      posizioneTelefono ??= await _leggiPosizioneDaConfig(
        _cfgPhoneLat,
        _cfgPhoneLon,
      );
      posizioneMaster ??= await _leggiPosizioneDaConfig(
        _cfgMasterLat,
        _cfgMasterLon,
      );
    }

    if (!mounted) return;
    setState(() {
      _centroFallback = posizioneTelefono;
      _centroMasterFallback = posizioneMaster;
      _centroInizialeRisolto = true;
    });
    _tryApplyInitialMapCenter();
  }

  void _aggiornaFallbackMasterDaLive(Map<int, TagDevice> tags) {
    final mastersConGps =
        tags.values
            .where(
              (tag) =>
                  tag.isMaster &&
                  tag.gpsValid &&
                  tag.latitude != null &&
                  tag.longitude != null,
            )
            .toList()
          ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

    if (mastersConGps.isEmpty) return;

    final ultimoMaster = mastersConGps.first;
    final nuovaPosizione = LatLng(
      ultimoMaster.latitude!,
      ultimoMaster.longitude!,
    );
    final precedente = _centroMasterFallback;
    final cambiata =
        precedente == null ||
        precedente.latitude != nuovaPosizione.latitude ||
        precedente.longitude != nuovaPosizione.longitude;

    if (cambiata && mounted) {
      setState(() => _centroMasterFallback = nuovaPosizione);
      unawaited(
        _salvaPosizioneConfig(
          keyLat: _cfgMasterLat,
          keyLon: _cfgMasterLon,
          pos: nuovaPosizione,
        ),
      );
    }
  }

  LatLng _centroMappa() {
    // Priorita': GPS telefono attuale/ultima nota.
    if (_centroFallback != null) {
      return _centroFallback!;
    }

    // Secondo fallback: ultima posizione nota di un master.
    if (_centroMasterFallback != null) {
      return _centroMasterFallback!;
    }

    // Fallback finale: Roma.
    return const LatLng(41.9028, 12.4964);
  }

  double? _raggioRicercaSlaveMetri() {
    final slaves = _slaveLive();
    if (slaves.isEmpty) return null;

    final distanze =
        slaves
            .map((tag) => BleUtils.stimaDistanza(tag.rssi))
            .where((d) => d.isFinite && d > 0)
            .toList()
          ..sort();

    if (distanze.isEmpty) return null;

    final idx90 = ((distanze.length - 1) * 0.9).round();
    final p90 = distanze[idx90];
    final raggio = p90 * 1.25;
    return raggio.clamp(20.0, 300.0);
  }

  void _tryApplyInitialMapCenter() {
    if (!_mapReady || _mappaInizializzata || !_centroInizialeRisolto) {
      return;
    }

    final mastersConGps = _mastersConGps();
    final centro = _centroMappa();
    final z oom = mastersConGps.length > 1 ? 12.0 : 14.0;

    _mapController.move(centro, zoom);

    if (!mounted) return;
    setState(() => _mappaInizializzata = true);
  }

  List<Marker> _markersMappa(List<TagDevice> masters, {LatLng? pastorePos}) {
    final markers = <Marker>[];

    if (pastorePos != null) {
      markers.add(
        Marker(
          point: pastorePos,
          width: 44,
          height: 44,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              color: const Color(0xFF2D9BFF),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.person_pin_circle, color: Colors.white),
          ),
        ),
      );
    }

    markers.addAll(
      masters.map((tag) {
        final punto = LatLng(tag.latitude!, tag.longitude!);
        final colore = tag.gatewayMode ? Colors.amber : const Color(0xFF2DFF6E);

        return Marker(
          point: punto,
          width: 56,
          height: 56,
          child: GestureDetector(
            onTap: () => _apriDettaglioMaster(tag),
            child: Container(
              decoration: BoxDecoration(
                color: colore.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                tag.gatewayMode ? Icons.place : Icons.pets,
                color: const Color(0xFF0A1A0F),
                size: 28,
              ),
            ),
          ),
        );
      }),
    );

    return markers;
  }

  Widget _buildMappaLive() {
    final isNomade = _numeroMaster == 0;
    final masters = _tags.values.where((tag) => tag.isMaster).toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    final List<TagDevice> mastersConGps = isNomade ? [] : _mastersConGps();
    final slavesLive = _slaveLive();
    final pastorePos = _centroFallback;
    final centro = isNomade && pastorePos != null ? pastorePos : _centroMappa();
    final raggioRicerca = _raggioRicercaSlaveMetri();

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          isNomade
              ? 'Mappa nomade: telefono come riferimento, ricerca slave nel raggio.'
              : 'Mappa ibrida: master come riferimento geografico principale.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 320,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: mastersConGps.length > 1 ? 12.0 : 14.0,
                    onMapReady: () {
                      _mapReady = true;
                      _tryApplyInitialMapCenter();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.greggesmart.app',
                    ),
                    if (pastorePos != null && raggioRicerca != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: pastorePos,
                            radius: raggioRicerca,
                            useRadiusInMeter: true,
                            color: const Color(
                              0xFF2D9BFF,
                            ).withValues(alpha: 0.18),
                            borderColor: const Color(0xFF2D9BFF),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: _markersMappa(
                        mastersConGps,
                        pastorePos: pastorePos,
                      ),
                    ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                if ((isNomade && pastorePos == null) ||
                    (!isNomade && mastersConGps.isEmpty))
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        isNomade
                            ? 'GPS telefono non disponibile al momento.'
                            : 'Nessun master con GPS valido al momento.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          isNomade
              ? 'Pastore (rif.GPS): ${pastorePos != null ? 'visibile' : 'no fix'}  |  Slave live: ${slavesLive.length}'
              : 'Pastore: ${pastorePos != null ? 'visibile' : 'no fix'}  |  Master live: ${masters.length}  |  Con GPS: ${mastersConGps.length}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          raggioRicerca != null
              ? 'Raggio ricerca slave (RSSI live): ~${raggioRicerca.round()} m  |  Slave live: ${slavesLive.length}'
              : 'Raggio ricerca slave non disponibile (serve almeno 1 slave live).',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    ];

    if (isNomade) {
      if (pastorePos == null) {
        children.add(
          const Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 28, 16, 8),
              child: Text(
                'Modalità nomade: attendo GPS del telefono...',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        );
      }
    } else if (masters.isEmpty) {
      children.add(
        const Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 28, 16, 8),
            child: Text(
              'Nessun master live al momento.',
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

    return Column(children: children);
  }

  Widget _buildMappaStorico() {
    final puntiFiltrati = _storicoPuntiFiltrati();
    final latLngPunti = puntiFiltrati
        .map((row) {
          final latRaw = row['latitude'];
          final lonRaw = row['longitude'];
          final lat = latRaw is num
              ? latRaw.toDouble()
              : double.tryParse('$latRaw');
          final lon = lonRaw is num
              ? lonRaw.toDouble()
              : double.tryParse('$lonRaw');
          if (lat == null || lon == null) return null;
          return LatLng(lat, lon);
        })
        .whereType<LatLng>()
        .toList();

    final centro = latLngPunti.isNotEmpty ? latLngPunti.first : _centroMappa();
    final tagDisponibili = _storicoTagDisponibili();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scegliGiornoStorico,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    '${_giornoStorico.day.toString().padLeft(2, '0')}/${_giornoStorico.month.toString().padLeft(2, '0')}/${_giornoStorico.year}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _storicoTagFilter,
                  dropdownColor: const Color(0xFF0F2318),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Tutti i tag'),
                    ),
                    ...tagDisponibili.map(
                      (id) => DropdownMenuItem<int?>(
                        value: id,
                        child: Text('Tag $id'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _storicoTagFilter = value);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 320,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: centro,
                      initialZoom: latLngPunti.length > 4 ? 13 : 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.greggesmart.app',
                      ),
                      if (latLngPunti.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: latLngPunti,
                              color: const Color(0xFFFFB703),
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      if (latLngPunti.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: latLngPunti.first,
                              width: 42,
                              height: 42,
                              child: const Icon(
                                Icons.play_circle_fill,
                                color: Color(0xFF2DFF6E),
                                size: 34,
                              ),
                            ),
                            Marker(
                              point: latLngPunti.last,
                              width: 42,
                              height: 42,
                              child: const Icon(
                                Icons.flag_circle,
                                color: Color(0xFFFF5D5D),
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                  if (_storicoLoading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    ),
                  if (!_storicoLoading && latLngPunti.isEmpty)
                    Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      alignment: Alignment.center,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Nessuna traccia GPS storica per questo giorno/filtro.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'Punti traccia: ${latLngPunti.length}  |  Giorno: ${_giornoStorico.day.toString().padLeft(2, '0')}/${_giornoStorico.month.toString().padLeft(2, '0')}/${_giornoStorico.year}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildMapTab() {
    return ListView(
      children: [
        const _SectionHeader(
          title: 'MAPPA GPS',
          subtitle: 'Live operativo e storico tracciato separati',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Live'),
                icon: Icon(Icons.radar),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Storico'),
                icon: Icon(Icons.timeline),
              ),
            ],
            selected: {_mapModeIndex},
            onSelectionChanged: (selection) {
              setState(() => _mapModeIndex = selection.first);
              if (selection.first == 1) {
                _caricaTracciaStorico();
              }
            },
          ),
        ),
        if (_mapModeIndex == 0) _buildMappaLive() else _buildMappaStorico(),
      ],
    );
  }

  Widget _buildDataTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Live'),
                icon: Icon(Icons.radar),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Albero'),
                icon: Icon(Icons.account_tree),
              ),
            ],
            selected: {_dataModeIndex},
            onSelectionChanged: (selection) {
              setState(() => _dataModeIndex = selection.first);
            },
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _dataModeIndex,
            children: [_buildLiveTab(), _buildTreeTab()],
          ),
        ),
      ],
    );
  }

  Future<void> _onMenuAction(String value) async {
    if (value == 'settings') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImpostazioniScreen()),
      );
      _ricaricaDati();
      return;
    }

    if (value == 'database') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DatabaseViewerScreen()),
      );
      return;
    }

    if (value == 'login' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login: in arrivo nelle prossime versioni.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _selectedTabIndex == 0
        ? (_dataModeIndex == 0 ? 'Live BLE' : 'Albero')
        : 'Mappa';

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: Text(currentTitle, style: TextStyle(color: Color(0xFF2DFF6E))),
        actions: [
          Icon(
            _bluetoothOn ? Icons.bluetooth : Icons.bluetooth_disabled,
            color: _bluetoothOn ? const Color(0xFF2DFF6E) : Colors.red,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop : Icons.play_arrow,
              color: const Color(0xFF2DFF6E),
            ),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF2DFF6E)),
            color: const Color(0xFF0F2318),
            onSelected: _onMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'database',
                child: Text('Database', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem<String>(
                value: 'settings',
                child: Text(
                  'Impostazioni',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem<String>(
                value: 'login',
                child: Text(
                  'Login (presto)',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [_buildDataTab(), _buildMapTab()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex == 0 ? 0 : 2,
        onTap: (index) {
          if (index == 1) {
            if (!_downloadInProgress) {
              _scaricaDaGatewayUnificato();
            }
          } else {
            setState(() => _selectedTabIndex = index < 2 ? 0 : 1);
          }
        },
        backgroundColor: const Color(0xFF0F2318),
        selectedItemColor: const Color(0xFF2DFF6E),
        unselectedItemColor: Colors.white54,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dati',
          ),
          BottomNavigationBarItem(
            icon: _downloadInProgress
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF2DFF6E),
                      ),
                    ),
                  )
                : const Icon(Icons.cloud_download),
            label: 'Aggiorna',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mappa'),
        ],
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

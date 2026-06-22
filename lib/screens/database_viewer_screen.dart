import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

class DatabaseViewerScreen extends StatefulWidget {
  const DatabaseViewerScreen({super.key});

  @override
  State<DatabaseViewerScreen> createState() => _DatabaseViewerScreenState();
}

class _DatabaseViewerScreenState extends State<DatabaseViewerScreen> {
  final _db = DatabaseService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;
  List<Map<String, Object?>> _pecore = [];
  List<Map<String, Object?>> _master = [];
  List<Map<String, Object?>> _config = [];
  List<Map<String, Object?>> _storico = [];
  Map<int, String> _nomiPecoreByTag = {};
  Map<int, String> _nomiMasterByTag = {};
  Map<String, int> _importBatchCountByTs = {};

  String _searchText = '';
  int? _tagFilter;
  int? _masterFilter;
  DateTime? _dayFilter;
  bool _includiEventiTelefono = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = await _db.database;

    final pecore = await db.query('pecore', orderBy: 'nome ASC');
    final master = await db.query('master', orderBy: 'created_at ASC');
    final config = await db.query('configurazione', orderBy: 'chiave ASC');
    final storico = await db.rawQuery('''
      SELECT id, tag_id, master_id, timestamp, imported_at, rssi, battery_pct,
             temperature, gps_valid, latitude, longitude
      FROM storico
      ORDER BY COALESCE(imported_at, timestamp) DESC, id DESC
      LIMIT 250
    ''');

    final batchCountByTs = <String, int>{};
    for (final row in storico) {
      final importedAt = '${row['imported_at'] ?? ''}'.trim();
      if (importedAt.isEmpty) continue;
      batchCountByTs[importedAt] = (batchCountByTs[importedAt] ?? 0) + 1;
    }

    if (!mounted) return;
    setState(() {
      _pecore = pecore;
      _master = master;
      _config = config;
      _storico = storico;
      _importBatchCountByTs = batchCountByTs;
      _nomiPecoreByTag = {
        for (final row in pecore)
          if (_intOrNull(row['tag_id']) != null)
            _intOrNull(row['tag_id'])!: '${row['nome'] ?? '-'}',
      };
      _nomiMasterByTag = {
        for (final row in master)
          if (_intOrNull(row['tag_id']) != null)
            _intOrNull(row['tag_id'])!: '${row['nome'] ?? '-'}',
      };
      if (_tagFilter != null && !_tagOptions().contains(_tagFilter)) {
        _tagFilter = null;
      }
      if (_masterFilter != null && !_masterOptions().contains(_masterFilter)) {
        _masterFilter = null;
      }
      _loading = false;
    });
  }

  int? _intOrNull(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  String _idHex(Object? raw) {
    final id = _intOrNull(raw);
    if (id == null || id <= 0) return '-';
    return '0x${id.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  String _labelTag(int id) {
    final nomeSlave = _nomiPecoreByTag[id];
    if (nomeSlave != null && nomeSlave.trim().isNotEmpty) {
      return '$nomeSlave (${_idHex(id)})';
    }

    final nomeMaster = _nomiMasterByTag[id];
    if (nomeMaster != null && nomeMaster.trim().isNotEmpty) {
      return '$nomeMaster (${_idHex(id)})';
    }

    return _idHex(id);
  }

  String _ruoloTag(int? tagId) {
    if (tagId == null || tagId <= 0) return 'TAG';
    if (_nomiPecoreByTag.containsKey(tagId)) return 'SLAVE';
    if (_nomiMasterByTag.containsKey(tagId)) return 'MASTER';
    return 'TAG';
  }

  String _nomeTag(int? tagId) {
    if (tagId == null || tagId <= 0) return '-';
    if (_nomiPecoreByTag.containsKey(tagId)) return _nomiPecoreByTag[tagId]!;
    if (_nomiMasterByTag.containsKey(tagId)) return _nomiMasterByTag[tagId]!;
    return '-';
  }

  String _formatDataOraEu(Object? raw) {
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final dt = DateTime.tryParse(text);
    if (dt == null) return text;
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString().padLeft(4, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  DateTime? _parseDateTime(Object? raw) {
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String _formatDelta(Duration delta) {
    final total = delta.inSeconds.abs();
    final hh = (total ~/ 3600).toString().padLeft(2, '0');
    final mm = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _gpsLabel(Map<String, Object?> row) {
    final gpsValid = _intOrNull(row['gps_valid']) == 1;
    final latRaw = row['latitude'];
    final lonRaw = row['longitude'];
    final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw');
    final lon = lonRaw is num ? lonRaw.toDouble() : double.tryParse('$lonRaw');

    if (gpsValid && lat != null && lon != null) {
      return 'FIX ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    }
    if (gpsValid) return 'FIX (coord non disponibili)';
    if (lat != null && lon != null) {
      return 'NO FIX (ultima: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)})';
    }
    return 'NO FIX';
  }

  ({String label, bool isGateway}) _origineEvento(Map<String, Object?> row) {
    final importedRaw = '${row['imported_at'] ?? ''}'.trim();
    if (importedRaw.isEmpty) {
      return (label: 'LIVE', isGateway: false);
    }

    final batchCount = _importBatchCountByTs[importedRaw] ?? 0;
    final ts = _parseDateTime(row['timestamp']);
    final imp = _parseDateTime(row['imported_at']);
    final delta = (ts != null && imp != null) ? imp.difference(ts) : null;
    final deltaSec = delta?.inSeconds.abs() ?? 0;

    if (batchCount > 1) {
      return (label: 'GATEWAY x$batchCount', isGateway: true);
    }
    if (deltaSec >= 3) {
      return (
        label: 'GATEWAY (delta ${_formatDelta(delta!)})',
        isGateway: true,
      );
    }
    return (label: 'SCARICO', isGateway: true);
  }

  List<int> _tagOptions() {
    final ids = <int>{};
    for (final row in _storico) {
      final id = _intOrNull(row['tag_id']);
      if (id != null && id > 0) ids.add(id);
    }
    return ids.toList()..sort();
  }

  List<int> _masterOptions() {
    final ids = <int>{};
    for (final row in _storico) {
      final id = _intOrNull(row['master_id']);
      if (id != null && id > 0) ids.add(id);
    }
    return ids.toList()..sort();
  }

  Set<int> _masterIdsStorici() {
    final ids = <int>{};
    for (final row in _storico) {
      final id = _intOrNull(row['master_id']);
      if (id != null && id > 0) ids.add(id);
    }
    return ids;
  }

  Set<int> _slaveIdsStorici() {
    final masterIds = _masterIdsStorici();
    final ids = <int>{};
    for (final row in _storico) {
      final tagId = _intOrNull(row['tag_id']);
      if (tagId == null || tagId <= 0) continue;
      if (masterIds.contains(tagId)) continue;
      ids.add(tagId);
    }
    return ids;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<Map<String, Object?>> _storicoFiltrato() {
    final query = _searchText.trim().toLowerCase();

    return _storico.where((row) {
      final tagId = _intOrNull(row['tag_id']);
      final masterId = _intOrNull(row['master_id']);
      final timestamp = '${row['timestamp'] ?? ''}';

      if (!_includiEventiTelefono && (masterId == null || masterId <= 0)) {
        return false;
      }

      if (_tagFilter != null && tagId != _tagFilter) return false;
      if (_masterFilter != null && masterId != _masterFilter) return false;

      if (_dayFilter != null) {
        final ts = DateTime.tryParse(timestamp);
        if (ts == null || !_sameDay(ts, _dayFilter!)) return false;
      }

      if (query.isEmpty) return true;

      final haystack = [
        _idHex(tagId),
        _idHex(masterId),
        '$tagId',
        '$masterId',
        '${row['rssi'] ?? ''}',
        '${row['battery_pct'] ?? ''}',
        timestamp,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dayFilter ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _dayFilter = picked);
  }

  void _clearFilters() {
    setState(() {
      _searchText = '';
      _searchController.clear();
      _tagFilter = null;
      _masterFilter = null;
      _dayFilter = null;
      _includiEventiTelefono = false;
    });
  }

  String _csvEscape(Object? value) {
    final raw = value?.toString() ?? '';
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    final rows = _storicoFiltrato();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun record da esportare con i filtri attuali.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final dbPath = await getDatabasesPath();
      final exportDir = Directory(p.join(dbPath, 'exports'));
      await exportDir.create(recursive: true);

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final outPath = p.join(exportDir.path, 'storico_export_$stamp.csv');

      final buffer = StringBuffer();
      const headers = [
        'id',
        'tag_id',
        'master_id',
        'timestamp',
        'imported_at',
        'rssi',
        'battery_pct',
        'temperature',
        'gps_valid',
        'latitude',
        'longitude',
      ];

      buffer.writeln(headers.join(','));
      for (final row in rows) {
        buffer.writeln(headers.map((h) => _csvEscape(row[h])).join(','));
      }

      await File(outPath).writeAsString(buffer.toString(), flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV esportato (${rows.length} righe): $outPath'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore export CSV: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _buildCountTile(String title, int value, Color color) {
    return Expanded(
      child: Card(
        color: const Color(0xFF0F2318),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListSection({
    required String title,
    required List<Map<String, Object?>> rows,
    required Widget Function(Map<String, Object?> row) tileBuilder,
  }) {
    return Card(
      color: const Color(0xFF0F1F3D),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        iconColor: const Color(0xFF2DFF6E),
        collapsedIconColor: Colors.white54,
        title: Text(
          '$title (${rows.length})',
          style: const TextStyle(color: Colors.white),
        ),
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nessun dato',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ...rows.map(tileBuilder),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFiltersCard() {
    final tagOptions = _tagOptions();
    final masterOptions = _masterOptions();

    return Card(
      color: const Color(0xFF0F2318),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchText = value),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Cerca per tag, master, timestamp, RSSI...',
                hintStyle: TextStyle(color: Colors.white54),
                prefixIcon: Icon(Icons.search, color: Color(0xFF2DFF6E)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2DFF6E)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _includiEventiTelefono,
              activeThumbColor: const Color(0xFF2DFF6E),
              title: const Text(
                'Includi eventi slave -> telefono',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Se disattivo, mostra solo record con master reale',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onChanged: (value) {
                setState(() => _includiEventiTelefono = value);
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _tagFilter,
                    dropdownColor: const Color(0xFF0F2318),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Tag',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Tutti i tag'),
                      ),
                      ...tagOptions.map(
                        (id) => DropdownMenuItem<int?>(
                          value: id,
                          child: Text(_labelTag(id)),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _tagFilter = value),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _masterFilter,
                    dropdownColor: const Color(0xFF0F2318),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Master',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Tutti i master'),
                      ),
                      ...masterOptions.map(
                        (id) => DropdownMenuItem<int?>(
                          value: id,
                          child: Text(_labelTag(id)),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _masterFilter = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _dayFilter == null
                          ? 'Tutti i giorni'
                          : '${_dayFilter!.day.toString().padLeft(2, '0')}/${_dayFilter!.month.toString().padLeft(2, '0')}/${_dayFilter!.year}',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text(
                    'Azzera filtri',
                    style: TextStyle(color: Color(0xFF2DFF6E)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storicoFiltrato = _storicoFiltrato();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        title: const Text(
          'Database',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2DFF6E)),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Color(0xFF2DFF6E)),
          ),
          _exporting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _exportCsv,
                  icon: const Icon(
                    Icons.file_download,
                    color: Color(0xFF2DFF6E),
                  ),
                ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2DFF6E)),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: ListView(
                children: [
                  Row(
                    children: [
                      _buildCountTile(
                        'Slave totali',
                        _slaveIdsStorici().length,
                        const Color(0xFF2DFF6E),
                      ),
                      _buildCountTile(
                        'Master totali',
                        _masterIdsStorici().length,
                        const Color(0xFF2D9BFF),
                      ),
                      _buildCountTile(
                        'Storico',
                        storicoFiltrato.length,
                        const Color(0xFFFFB703),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildFiltersCard(),
                  _buildListSection(
                    title: 'Master',
                    rows: _master,
                    tileBuilder: (row) {
                      final nome = (row['nome'] as String?) ?? '-';
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: 0,
                          vertical: -3,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        title: Text(
                          nome,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          '${_idHex(row['tag_id'])}  |  RFID: ${row['rfid'] ?? '-'}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildListSection(
                    title: 'Pecore',
                    rows: _pecore,
                    tileBuilder: (row) {
                      final nome = (row['nome'] as String?) ?? '-';
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: 0,
                          vertical: -3,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        title: Text(
                          nome,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          '${_idHex(row['tag_id'])}  |  RFID: ${row['rfid'] ?? '-'}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildListSection(
                    title: 'Storico filtrato (ultimi 250)',
                    rows: storicoFiltrato,
                    tileBuilder: (row) {
                      final tagId = _intOrNull(row['tag_id']);
                      final masterId = _intOrNull(row['master_id']);
                      final tagHex = _idHex(tagId);
                      final masterHex = _idHex(masterId);
                      final ruolo = _ruoloTag(tagId);
                      final nomeTag = _nomeTag(tagId);
                      final nomeMaster = _nomeTag(masterId);
                      final hasMaster = masterId != null && masterId > 0;
                      final targetLabel = hasMaster
                          ? 'MASTER $masterHex ($nomeMaster)'
                          : 'APP/TELEFONO';
                      final gpsText = _gpsLabel(row);
                      final ts = _parseDateTime(row['timestamp']);
                      final imp = _parseDateTime(row['imported_at']);
                      final tsFmt = _formatDataOraEu(row['timestamp']);
                      final impFmt = _formatDataOraEu(row['imported_at']);
                      final sameTime =
                          ts != null &&
                          imp != null &&
                          ts.difference(imp).inSeconds.abs() < 2;
                      final origine = _origineEvento(row);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1830),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$ruolo $tagHex ($nomeTag)  ->  $targetLabel',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: origine.isGateway
                                      ? const Color(0xFF2D9BFF)
                                      : const Color(0xFF2DFF6E),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  origine.label,
                                  style: const TextStyle(
                                    color: Color(0xFF0A1A0F),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'RSSI ${row['rssi']}  |  Bat ${row['battery_pct']}%  |  Temp ${row['temperature']}°C',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'GPS: $gpsText',
                              style: TextStyle(
                                color: gpsText.startsWith('FIX')
                                    ? const Color(0xFF2DFF6E)
                                    : Colors.orange.shade200,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              imp == null
                                  ? 'Evento/Fix: $tsFmt  |  Scarico: -'
                                  : sameTime
                                  ? 'Scarico: $impFmt'
                                  : 'Evento/Fix: $tsFmt  |  Scarico: $impFmt',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  _buildListSection(
                    title: 'Configurazione',
                    rows: _config,
                    tileBuilder: (row) => ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(
                        horizontal: 0,
                        vertical: -3,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      title: Text(
                        '${row['chiave']}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${row['valore']}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
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

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

class SupabaseScreen extends StatefulWidget {
  const SupabaseScreen({super.key});

  @override
  State<SupabaseScreen> createState() => _SupabaseScreenState();
}

class _SupabaseScreenState extends State<SupabaseScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _busy = false;
  String? _msg;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refreshPending();
  }

  Future<void> _refreshPending() async {
    final count = await _supabaseService.getPendingSyncCount();
    if (!mounted) return;
    setState(() => _pending = count);
  }

  Future<void> _testConnection() async {
    if (!_supabaseService.isConfigured) {
      setState(() {
        _msg = 'Configura URL e anon key in lib/supabase/supabase_config.dart';
      });
      return;
    }

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      final msg = await _supabaseService.testConnection();
      if (!mounted) return;
      setState(() => _msg = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Errore connessione: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _syncNow() async {
    if (!_supabaseService.isConfigured) {
      setState(() {
        _msg = 'Configura URL e anon key in lib/supabase/supabase_config.dart';
      });
      return;
    }

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      final report = await _supabaseService.syncDeltaToCloud();
      if (!mounted) return;
      setState(() {
        _msg =
        'Sync DELTA OK | tenant: ${report.tenantId}\n'
            'pecore: ${report.pecoreCount}, master: ${report.masterCount}, '
            'storico: ${report.storicoCount}, config: ${report.configurazioneCount}';
      });
      await _refreshPending();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Errore sync: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncFullReseed() async {
    if (!_supabaseService.isConfigured) {
      setState(() {
        _msg = 'Configura URL e anon key in lib/supabase/supabase_config.dart';
      });
      return;
    }

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      await _supabaseService.resetStoricoSyncCursor();
      final report = await _supabaseService.syncAllToCloud();
      if (!mounted) return;
      setState(() {
        _msg =
            'Sync COMPLETA OK | tenant: ${report.tenantId}\n'
            'pecore: ${report.pecoreCount}, master: ${report.masterCount}, '
            'storico: ${report.storicoCount}, config: ${report.configurazioneCount}';
      });
      await _refreshPending();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Errore sync completa: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPending() async {
    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      final result = await _supabaseService.retryPendingIfOnline();
      if (!mounted) return;
      if (result == null) {
        setState(() => _msg = 'Nessuna sync in coda.');
      } else {
        setState(() => _msg = result.message);
      }
      await _refreshPending();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = 'Errore retry: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2318),
        iconTheme: const IconThemeData(color: Color(0xFF2DFF6E)),
        title: const Text(
          'Cloud e Sync',
          style: TextStyle(color: Color(0xFF2DFF6E)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SUPABASE',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sync in coda (offline): $_pending',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                'Configura URL e anon key in lib/supabase/supabase_config.dart',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _testConnection,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2DFF6E)),
                        foregroundColor: const Color(0xFF2DFF6E),
                      ),
                      child: const Text('TEST CONNESSIONE'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _syncNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2DFF6E),
                        foregroundColor: Colors.black,
                      ),
                      child: Text(_busy ? 'SYNC...' : 'SYNC ORA'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : _retryPending,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white30),
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('RIPROVA CODA OFFLINE'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : _syncFullReseed,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orangeAccent),
                    foregroundColor: Colors.orangeAccent,
                  ),
                  child: const Text('FORZA SYNC COMPLETA (RESEED)'),
                ),
              ),
              if (_msg != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _msg!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

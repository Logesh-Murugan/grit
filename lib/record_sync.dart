import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable local outbox. All server access passes an Admin revocation check.
/// Deployment must be enabled explicitly; there is no direct Firestore fallback.
class RecordSync {
  RecordSync(
      {required this.uid,
      required this.prefs,
      required this.receive,
      required this.status});
  final String uid;
  final SharedPreferences? prefs;
  final void Function(Map<String, dynamic>) receive;
  final void Function(String) status;
  final Map<String, Map<String, dynamic>> _pending = {};
  final Map<String, String> _seen = {};
  Timer? _retry;
  bool _flushing = false, _polling = false, _closed = false;
  int _serial = 0;
  static const enabled = bool.fromEnvironment('SECURE_SYNC_ENABLED');
  String get _key => 'grit.v2.$uid.outbox';
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  Future<void> start() async {
    final raw = prefs?.getString(_key);
    if (raw != null) {
      final data = Map<String, dynamic>.from(jsonDecode(raw));
      for (final entry in data.entries) {
        _pending[entry.key] = Map<String, dynamic>.from(entry.value);
      }
    }
    if (!enabled) {
      status('Cloud sync is not connected yet. Saved on this device.');
      return;
    }
    _retry =
        Timer.periodic(const Duration(seconds: 10), (_) => unawaited(cycle()));
    unawaited(cycle());
  }

  Future<void> cycle() async {
    if (_closed) return;
    await flush();
    await poll();
  }

  Future<void> poll() async {
    if (!enabled || _closed || _polling) return;
    _polling = true;
    try {
      String? after;
      do {
        final result = await _functions
            .httpsCallable('readRecords')
            .call({'after': after});
        if (_closed) return;
        final data = Map<String, dynamic>.from(result.data);
        for (final item in data['records'] as List) {
          final record = Map<String, dynamic>.from(item);
          final key = record.remove('key') as String;
          if (_pending.containsKey(key)) continue;
          final signature = jsonEncode(record);
          if (_seen[key] != signature) {
            receive(record);
            _seen[key] = signature;
          }
        }
        after = data['after'] as String?;
      } while (after != null && !_closed);
    } on FirebaseFunctionsException catch (e) {
      if (!_closed) {
        status(e.code == 'unauthenticated'
            ? 'Your cloud session ended. Sign out and sign in again; local edits are safe.'
            : 'Cloud unavailable. Your tasks remain saved on this device.');
      }
    } catch (_) {
      if (!_closed) {
        status('Cloud unavailable. Your tasks remain saved on this device.');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> enqueue(Map<String, Map<String, dynamic>> changes) async {
    if (_closed) return;
    for (final entry in changes.entries) {
      _pending[entry.key] = {
        ...entry.value,
        'mutation': '${DateTime.now().microsecondsSinceEpoch}-${_serial++}'
      };
    }
    await prefs?.setString(_key, jsonEncode(_pending));
    unawaited(flush());
  }

  Future<void> flush() async {
    if (!enabled || _flushing || _closed || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty && !_closed) {
        final sent = Map<String, Map<String, dynamic>>.fromEntries(
            _pending.entries.take(100));
        await _functions
            .httpsCallable('writeRecords')
            .call({'records': sent.values.toList()});
        if (_closed) return;
        for (final entry in sent.entries) {
          if (_pending[entry.key]?['mutation'] == entry.value['mutation']) {
            _pending.remove(entry.key);
          }
        }
        await prefs?.setString(_key, jsonEncode(_pending));
      }
      status('');
    } on FirebaseFunctionsException catch (e) {
      if (!_closed) {
        status(e.code == 'unauthenticated'
            ? 'Your cloud session ended. Sign out and sign in again; local edits are safe.'
            : 'Edits saved locally; waiting for secure cloud sync.');
      }
    } catch (_) {
      if (!_closed) {
        status('Edits saved locally; waiting for secure cloud sync.');
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
  }
}

Map<String, Map<String, dynamic>> workspaceRecords(
    Map<String, dynamic> workspace) {
  final result = <String, Map<String, dynamic>>{};
  for (final type in ['tasks', 'projects', 'events', 'filters']) {
    for (final item in workspace[type] as List? ?? []) {
      final data = Map<String, dynamic>.from(item);
      // Bytes stay device-local until object-storage uploads are configured.
      if (type == 'tasks') data['attachments'] = <dynamic>[];
      final id = data['id'] as String;
      result['$type-${Uri.encodeComponent(id)}'] = {
        'type': type,
        'id': id,
        'data': data,
        'deleted': false
      };
    }
  }
  final settings = Map<String, dynamic>.from(workspace)
    ..removeWhere((key, value) =>
        ['tasks', 'projects', 'events', 'filters'].contains(key));
  result['settings'] = {
    'type': 'settings',
    'id': 'settings',
    'data': settings,
    'deleted': false
  };
  return result;
}

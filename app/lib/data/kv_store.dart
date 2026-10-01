import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Tiny JSON key-value store kept in the app-private files directory
/// (`prefs.json` by default). Used for lightweight device state: login
/// session, learning preferences, recent searches, podcast subscriptions.
///
/// Mirrors the corruption-tolerant policy of [LocalLibraryStore]: an
/// unreadable index is quarantined and the store starts empty instead of
/// crashing the app at launch. Writes are serialized through a single
/// chain (each snapshot taken in call order, flushed strictly one after
/// another onto a unique temp file + rename), so concurrent `set`/`remove`
/// calls during startup can never reorder and resurrect a stale value.
class KvStore {
  KvStore(this.filesDir, {this.fileName = 'prefs.json'});

  final Directory filesDir;
  final String fileName;
  final Map<String, dynamic> _values = {};

  /// Tail of the write chain; every mutation appends to it.
  Future<void> _writeChain = Future<void>.value();
  int _writeSeq = 0;

  File get _file =>
      File('${filesDir.path}${Platform.pathSeparator}$fileName');

  static Future<KvStore> open(Directory dir, {String fileName = 'prefs.json'}) async {
    final store = KvStore(dir, fileName: fileName);
    await store.load();
    return store;
  }

  Future<void> load() async {
    _values.clear();
    if (!_file.existsSync()) return;
    try {
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) _values.addAll(decoded);
    } catch (_) {
      try {
        final backup = File('${_file.path}.corrupt-'
            '${DateTime.now().millisecondsSinceEpoch}');
        _file.renameSync(backup.path);
      } catch (_) {
        // Quarantine is best effort.
      }
      _values.clear();
    }
  }

  dynamic get(String key) => _values[key];

  String? getString(String key) => _values[key] as String?;

  bool? getBool(String key) => _values[key] as bool?;

  List<String> getStringList(String key) =>
      (_values[key] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();

  Future<void> set(String key, dynamic value) {
    _values[key] = value;
    return _scheduleWrite();
  }

  Future<void> remove(String key) {
    if (!_values.containsKey(key)) return Future<void>.value();
    _values.remove(key);
    return _scheduleWrite();
  }

  Future<void> clear() {
    _values.clear();
    return _scheduleWrite();
  }

  /// Snapshots the in-memory map synchronously (so the snapshot reflects
  /// every mutation issued up to this call) and appends an atomic flush to
  /// the chain. Returned future completes when *this* snapshot is durable.
  Future<void> _scheduleWrite() {
    final snapshot = const JsonEncoder.withIndent('  ').convert(_values);
    final seq = ++_writeSeq;
    final completer = Completer<void>();
    _writeChain = _writeChain.then((_) async {
      final tmp = File('${_file.path}.tmp.$seq');
      try {
        filesDir.createSync(recursive: true);
        await tmp.writeAsString(snapshot, flush: true);
        tmp.renameSync(_file.path);
        completer.complete();
      } catch (e, st) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {
          // Cleanup is best effort.
        }
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

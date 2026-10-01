import 'dart:convert';
import 'dart:io';

import '../domain/entities/recording.dart';

/// JSON-file-backed index of shadowing recordings
/// (`recordings_index.json`), same persistence/quarantine pattern as
/// [LocalLibraryStore]. The audio files themselves live in the recorder's
/// sandbox folder; this index only stores metadata.
class PracticeStore {
  PracticeStore(this.filesDir);

  final Directory filesDir;
  final List<Recording> entries = [];

  File get _indexFile => File('${filesDir.path}${Platform.pathSeparator}'
      'recordings_index.json');

  static Future<PracticeStore> open(Directory dir) async {
    final store = PracticeStore(dir);
    await store.load();
    return store;
  }

  Future<void> load() async {
    entries.clear();
    if (!_indexFile.existsSync()) return;
    try {
      final raw = await _indexFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      entries.addAll(list.map(
          (e) => Recording.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      try {
        final backup = File('${_indexFile.path}.corrupt-'
            '${DateTime.now().millisecondsSinceEpoch}');
        _indexFile.renameSync(backup.path);
      } catch (_) {
        // Quarantine is best effort.
      }
      entries.clear();
    }
  }

  /// Insert or replace (same id), mirroring the memory repository contract.
  Future<void> upsert(Recording recording) async {
    entries.removeWhere((r) => r.id == recording.id);
    entries.add(recording);
    await _save();
  }

  Future<Recording?> remove(String id) async {
    final i = entries.indexWhere((r) => r.id == id);
    if (i < 0) return null;
    final removed = entries.removeAt(i);
    await _save();
    return removed;
  }

  Future<void> clear() async {
    if (entries.isEmpty) return;
    entries.clear();
    await _save();
  }

  Future<void> _save() async {
    filesDir.createSync(recursive: true);
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        entries.map((e) => e.toJson()).toList(),
      ),
    );
    tmp.renameSync(_indexFile.path);
  }
}

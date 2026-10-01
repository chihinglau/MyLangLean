import 'dart:io';

import '../../domain/entities/recording.dart';
import '../../domain/repositories/repositories.dart';
import '../practice_store.dart';

/// Production practice repository: recordings persist in
/// `recordings_index.json` and survive app restarts. Deleting a record also
/// removes its sandbox audio file (best effort).
class PersistentPracticeRepository implements PracticeRepository {
  PersistentPracticeRepository(this._store);

  final PracticeStore _store;

  @override
  List<Recording> recordings() {
    final items = List<Recording>.of(_store.entries);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<Recording> save(Recording recording) async {
    await _store.upsert(recording);
    return recording;
  }

  @override
  Future<void> delete(String id) async {
    final removed = await _store.remove(id);
    if (removed == null) return;
    _deleteQuietly(removed.filePath);
  }

  @override
  Future<void> clear() async {
    final files = _store.entries.map((r) => r.filePath).toList();
    await _store.clear();
    for (final path in files) {
      _deleteQuietly(path);
    }
  }

  @override
  int totalPracticeSec() =>
      _store.entries.fold(0, (sum, r) => sum + r.practiceMs) ~/ 1000;

  void _deleteQuietly(String path) {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Index consistency matters more than file cleanup.
    }
  }
}

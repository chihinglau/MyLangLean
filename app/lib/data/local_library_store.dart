import 'dart:convert';
import 'dart:io';

import '../domain/entities/episode.dart';

/// One imported media row in [LocalLibraryStore].
class LocalMediaEntry {
  const LocalMediaEntry({
    required this.id,
    required this.title,
    required this.mediaPath,
    this.transcriptPath,
    this.durationMs = 0,
    this.language = 'en',
    required this.importedAt,
  });

  final String id;
  final String title;
  final String mediaPath;
  final String? transcriptPath;
  final int durationMs;
  final String language;
  final DateTime importedAt;

  Episode toEpisode() => Episode(
        id: id,
        title: title,
        audioUrl: mediaPath,
        duration: Duration(milliseconds: durationMs),
        pubDate: importedAt,
        isLocal: true,
        localPath: mediaPath,
        transcriptPath: transcriptPath,
        language: language,
      );

  LocalMediaEntry copyWith({String? transcriptPath, String? title}) =>
      LocalMediaEntry(
        id: id,
        title: title ?? this.title,
        mediaPath: mediaPath,
        transcriptPath: transcriptPath ?? this.transcriptPath,
        durationMs: durationMs,
        language: language,
        importedAt: importedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'mediaPath': mediaPath,
        'transcriptPath': transcriptPath,
        'durationMs': durationMs,
        'language': language,
        'importedAt': importedAt.toIso8601String(),
      };

  factory LocalMediaEntry.fromJson(Map<String, dynamic> json) =>
      LocalMediaEntry(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        mediaPath: json['mediaPath'] as String,
        transcriptPath: json['transcriptPath'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        language: json['language'] as String? ?? 'en',
        importedAt:
            DateTime.tryParse(json['importedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// JSON-file-backed index of imported media, kept in the app-private files
/// directory. Corruption is non-fatal: the bad index is quarantined and the
/// library starts empty.
class LocalLibraryStore {
  LocalLibraryStore(this.filesDir);

  final Directory filesDir;
  final List<LocalMediaEntry> entries = [];

  File get _indexFile => File('${filesDir.path}${Platform.pathSeparator}'
      'library_index.json');

  static Future<LocalLibraryStore> open(Directory dir) async {
    final store = LocalLibraryStore(dir);
    await store.load();
    return store;
  }

  Future<void> load() async {
    entries.clear();
    if (!_indexFile.existsSync()) return;
    try {
      final raw = await _indexFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      entries.addAll(list.map((e) =>
          LocalMediaEntry.fromJson(e as Map<String, dynamic>)));
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

  Future<LocalMediaEntry> add({
    required String title,
    required String mediaPath,
    String? transcriptPath,
    int durationMs = 0,
    String language = 'en',
  }) async {
    final entry = LocalMediaEntry(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      mediaPath: mediaPath,
      transcriptPath: transcriptPath,
      durationMs: durationMs,
      language: language,
      importedAt: DateTime.now(),
    );
    entries.add(entry);
    await _save();
    return entry;
  }

  Future<LocalMediaEntry?> updateTranscript(
      String id, String? transcriptPath) async {
    final i = entries.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    entries[i] = entries[i].copyWith(transcriptPath: transcriptPath);
    await _save();
    return entries[i];
  }

  Future<LocalMediaEntry?> remove(String id) async {
    final i = entries.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    final removed = entries.removeAt(i);
    await _save();
    return removed;
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

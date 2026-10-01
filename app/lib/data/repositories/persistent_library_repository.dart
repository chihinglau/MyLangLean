import 'dart:io';

import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';
import '../../domain/repositories/repositories.dart';
import '../kv_store.dart';
import '../local_library_store.dart';

/// Production library repository: imported media is persisted through
/// [LocalLibraryStore] and podcast subscriptions through [KvStore]
/// (`subscriptions` key), so both survive app restarts.
class PersistentLibraryRepository implements LibraryRepository {
  PersistentLibraryRepository(this._store, [KvStore? kv]) : _kv = kv {
    _subscriptions.addAll(_loadSubscriptions());
  }

  final LocalLibraryStore _store;
  final KvStore? _kv;
  final List<Podcast> _subscriptions = [];

  static const _kSubscriptions = 'subscriptions';

  List<Podcast> _loadSubscriptions() {
    final raw = _kv?.get(_kSubscriptions);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Podcast.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _persistSubscriptions() async {
    await _kv?.set(
      _kSubscriptions,
      _subscriptions.map((p) => p.toJson()).toList(),
    );
  }

  /// Replaces the whole subscription set (used by server sync reconciliation).
  Future<void> replaceSubscriptions(Iterable<Podcast> items) async {
    _subscriptions
      ..clear()
      ..addAll(items);
    await _persistSubscriptions();
  }

  @override
  List<Podcast> subscriptions() => List.unmodifiable(_subscriptions);

  @override
  Future<void> toggleSubscription(Podcast podcast) async {
    final exists = _subscriptions.any((p) => p.id == podcast.id);
    if (exists) {
      _subscriptions.removeWhere((p) => p.id == podcast.id);
    } else {
      _subscriptions.add(podcast);
    }
    await _persistSubscriptions();
  }

  @override
  List<Episode> localMedia() =>
      _store.entries.map((e) => e.toEpisode()).toList();

  @override
  Future<Episode> addLocalMedia(
    String mediaPath, {
    String? transcriptPath,
    String? title,
    String? language,
    int? durationMs,
  }) async {
    final name = title ?? _basename(mediaPath);
    final entry = await _store.add(
      title: name,
      mediaPath: mediaPath,
      transcriptPath: transcriptPath,
      durationMs: durationMs ?? 0,
      language: language ?? 'en',
    );
    return entry.toEpisode();
  }

  @override
  Future<Episode?> attachTranscript(
      String episodeId, String transcriptPath) async {
    final entry = await _store.updateTranscript(episodeId, transcriptPath);
    return entry?.toEpisode();
  }

  @override
  Future<void> removeLocalMedia(String episodeId) async {
    final removed = await _store.remove(episodeId);
    if (removed == null) return;
    _deleteQuietly(removed.mediaPath);
    final sidecar = removed.transcriptPath;
    if (sidecar != null) _deleteQuietly(sidecar);
  }

  static String _basename(String path) =>
      path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Index consistency matters more than file cleanup.
    }
  }
}

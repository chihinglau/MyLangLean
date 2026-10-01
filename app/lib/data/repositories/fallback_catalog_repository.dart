import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';
import '../../domain/repositories/repositories.dart';
import '../kv_store.dart';
import '../mock/mock_catalog.dart';
import '../remote/ml_api.dart';

/// Online-first catalog:
///   1. try the PC service;
///   2. on any failure use the last successful snapshot cached in [KvStore];
///   3. finally fall back to the bundled [MockCatalog], so the discover page
///      is always populated even with no server at all.
class FallbackCatalogRepository implements CatalogRepository {
  FallbackCatalogRepository(this._api, [this._kv]);

  final MlApi _api;
  final KvStore? _kv;

  static const _kPodcasts = 'cache.catalog.podcasts';
  static const _kEpisodesPrefix = 'cache.catalog.episodes.';

  @override
  Future<List<Podcast>> featured(
      {ContentLevel? level, String? language}) async {
    try {
      final remote = await _api.podcasts();
      _cachePodcasts(remote);
      return remote;
    } catch (_) {
      final cached = _cachedPodcasts();
      if (cached != null) return cached;
      return MockCatalog.podcasts;
    }
  }

  @override
  Future<List<Podcast>> search(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return featured();
    try {
      final remote = await _api.podcasts(q: k);
      // Cache the full catalog opportunistically when the result is empty
      // (server search still succeeded - keep what we got; do not overwrite
      // a richer cache with an empty list).
      final cached = _cachedPodcasts();
      if (remote.isEmpty && cached != null && cached.isNotEmpty) {
        return _localSearch(cached, k);
      }
      if (remote.isNotEmpty && cached == null) {
        _cachePodcasts(remote);
      }
      return remote;
    } catch (_) {
      final source = _cachedPodcasts() ?? MockCatalog.podcasts;
      return _localSearch(source, k);
    }
  }

  @override
  Future<List<Episode>> episodesOf(Podcast podcast) async {
    try {
      final raw = await _api.episodes(podcast.id);
      final hydrated = raw
          .map((e) => _api.hydrateEpisode(e, podcast))
          .toList(growable: false);
      _cacheEpisodes(podcast.id, hydrated);
      return hydrated;
    } catch (_) {
      final cached = _cachedEpisodes(podcast.id);
      if (cached != null) return cached;
      // Bundled ids p1..p8 ship with playable asset:// sample episodes.
      if (MockCatalog.podcasts.any((p) => p.id == podcast.id)) {
        return MockCatalog.episodesOf(podcast.id);
      }
      return const [];
    }
  }

  // ---- offline matching ---------------------------------------------------

  List<Podcast> _localSearch(List<Podcast> source, String keyword) {
    final k = keyword.toLowerCase();
    return source
        .where((p) =>
            p.title.toLowerCase().contains(k) ||
            p.author.toLowerCase().contains(k) ||
            p.description.toLowerCase().contains(k) ||
            p.language.contains(k))
        .toList();
  }

  // ---- cache --------------------------------------------------------------
  //
  // Snapshots are stored as envelopes `{ts, content_version?, items}` so the
  // app knows when its offline copy was taken and can detect server content
  // changes. A bare legacy list is still read for forward compatibility.

  List<Podcast>? _cachedPodcasts() {
    final raw = _kv?.get(_kPodcasts);
    final items = raw is Map ? raw['items'] : raw;
    if (items is! List) return null;
    return items
        .whereType<Map>()
        .map((e) => Podcast.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void _cachePodcasts(List<Podcast> items) {
    final kv = _kv;
    if (kv == null) return;
    kv.set(_kPodcasts, {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'content_version': _api.lastCatalogVersion,
      'items': items.map((p) => p.toJson()).toList(),
    });
  }

  List<Episode>? _cachedEpisodes(String podcastId) {
    final raw = _kv?.get('$_kEpisodesPrefix$podcastId');
    final items = raw is Map ? raw['items'] : raw;
    if (items is! List) return null;
    return items
        .whereType<Map>()
        .map((e) => Episode.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void _cacheEpisodes(String podcastId, List<Episode> items) {
    final kv = _kv;
    if (kv == null) return;
    kv.set('$_kEpisodesPrefix$podcastId', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'items': items.map((e) => e.toJson()).toList(),
    });
  }
}

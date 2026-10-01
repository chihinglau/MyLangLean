import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';
import '../../domain/repositories/repositories.dart';
import '../kv_store.dart';
import '../remote/ml_api.dart';
import 'persistent_library_repository.dart';

/// One pending subscribe/unsubscribe action, keyed by podcast id.
class _PendingOp {
  const _PendingOp(this.podcastId, this.subscribe, this.at);

  final String podcastId;
  final bool subscribe;
  final int at;

  Map<String, dynamic> toJson() =>
      {'id': podcastId, 'sub': subscribe, 't': at};

  static _PendingOp fromJson(Map<String, dynamic> json) => _PendingOp(
        json['id'].toString(),
        json['sub'] == true,
        (json['t'] as num?)?.toInt() ?? 0,
      );
}

/// Online subscriptions + local media.
///
/// Subscription toggles apply locally first (instant UI), then sync to the
/// server. Every toggle is recorded in a per-id pending-op queue
/// (`subscriptions.pending`): network failures replay during
/// [syncSubscriptions], which guarantees that an offline **unsubscribe is
/// never "resurrected"** by the union merge. Reconcile order:
///   1. replay pending PUT/DELETE in time order;
///   2. pull server state;
///   3. push local-only subscriptions up;
///   4. merge, excluding ids whose latest pending op is unsubscribe.
class SyncedLibraryRepository implements LibraryRepository {
  SyncedLibraryRepository(this._inner, this._api, [this._kv]);

  final PersistentLibraryRepository _inner;
  final MlApi _api;
  final KvStore? _kv;

  static const _kPending = 'subscriptions.pending';

  List<_PendingOp> _readPending() {
    final raw = _kv?.get(_kPending);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => _PendingOp.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> _writePending(List<_PendingOp> ops) async {
    final kv = _kv;
    if (kv == null) return;
    if (ops.isEmpty) {
      await kv.remove(_kPending);
    } else {
      await kv.set(_kPending, ops.map((o) => o.toJson()).toList());
    }
  }

  /// Record the latest user intent for [podcastId] (last write wins).
  Future<void> _enqueue(String podcastId, bool subscribe) async {
    final ops = _readPending();
    ops.removeWhere((o) => o.podcastId == podcastId);
    ops.add(_PendingOp(
        podcastId, subscribe, DateTime.now().millisecondsSinceEpoch));
    await _writePending(ops);
  }

  Future<void> _forget(String podcastId) async {
    final ops = _readPending();
    if (ops.any((o) => o.podcastId == podcastId)) {
      ops.removeWhere((o) => o.podcastId == podcastId);
      await _writePending(ops);
    }
  }

  // ---- subscriptions ------------------------------------------------------

  @override
  List<Podcast> subscriptions() => _inner.subscriptions();

  @override
  Future<void> toggleSubscription(Podcast podcast) async {
    final wasSubscribed =
        _inner.subscriptions().any((p) => p.id == podcast.id);
    await _inner.toggleSubscription(podcast);
    final nowSubscribed = !wasSubscribed;
    if (!_api.isAuthenticated) {
      await _enqueue(podcast.id, nowSubscribed);
      return;
    }
    try {
      if (nowSubscribed) {
        await _api.subscribe(podcast.id);
      } else {
        await _api.unsubscribe(podcast.id);
      }
      await _forget(podcast.id);
    } catch (_) {
      // Keep the optimistic local state; replay during next sync.
      await _enqueue(podcast.id, nowSubscribed);
    }
  }

  /// Replays pending ops against the server. Returns the ops that could not
  /// be confirmed (still pending) and the ids whose subscribe failed with
  /// 404 (podcast unpublished/deleted — drop them locally too).
  Future<(Map<String, _PendingOp>, Set<String>)> _replayPending(
      List<_PendingOp> ops) async {
    final pending = <String, _PendingOp>{};
    final gone = <String>{};
    for (final op in ops) {
      try {
        if (op.subscribe) {
          await _api.subscribe(op.podcastId);
        } else {
          await _api.unsubscribe(op.podcastId);
        }
      } on MlApiException catch (e) {
        if (op.subscribe && e.statusCode == 404) {
          // Target no longer exists: the local subscription can never sync.
          gone.add(op.podcastId);
          continue;
        }
        pending[op.podcastId] = op;
      } catch (_) {
        pending[op.podcastId] = op;
      }
    }
    return (pending, gone);
  }

  /// Pulls server subscriptions and merges with the local mirror. Safe to
  /// call when offline or logged out (no-op). Returns true when a refresh of
  /// dependent UI is needed.
  Future<bool> syncSubscriptions() async {
    if (!_api.isAuthenticated) return false;

    // 1. Replay user intents recorded while offline / failing.
    final queued = _readPending()
      ..sort((a, b) => a.at.compareTo(b.at));
    final (pending, gone) = await _replayPending(queued);
    await _writePending(pending.values.toList()
      ..sort((a, b) => a.at.compareTo(b.at)));

    // 2. Pull server truth. If the pull itself fails, keep local state.
    List<Podcast> remote;
    try {
      remote = await _api.subscriptions();
    } catch (_) {
      return false;
    }

    final local = _inner.subscriptions();
    final remoteIds = remote.map((p) => p.id).toSet();
    final localIds = local.map((p) => p.id).toSet();

    // 3. Push local-only subscriptions up (best effort).
    await Future.wait(
      local
          .where((p) =>
              !remoteIds.contains(p.id) &&
              pending[p.id]?.subscribe != false &&
              !gone.contains(p.id))
          .map((p) async {
        try {
          await _api.subscribe(p.id);
          remoteIds.add(p.id);
          remote = [...remote, p];
        } catch (_) {
          // Stays local-only; a pending sub will make the next sync retry.
          await _enqueue(p.id, true);
        }
      }),
    );

    // 4. Merge: server metadata wins; local-only entries are kept unless the
    //    latest confirmed/pending user intent is unsubscribe.
    final byId = <String, Podcast>{};
    for (final p in remote) {
      if (pending[p.id]?.subscribe == false) continue;
      byId[p.id] = p;
    }
    for (final p in local) {
      if (gone.contains(p.id)) continue;
      if (pending[p.id]?.subscribe == false) continue;
      byId.putIfAbsent(p.id, () => p);
    }

    final mergedIds = byId.keys.toSet();
    final changed = !mergedIds.containsAll(localIds) ||
        !localIds.containsAll(mergedIds) ||
        gone.isNotEmpty;
    await _inner.replaceSubscriptions(mergedIds.isEmpty
        ? const []
        : byId.values.toList(growable: false));
    return changed;
  }

  // ---- local media (pure delegation to the persistent store) --------------

  @override
  List<Episode> localMedia() => _inner.localMedia();

  @override
  Future<Episode> addLocalMedia(
    String mediaPath, {
    String? transcriptPath,
    String? title,
    String? language,
    int? durationMs,
  }) =>
      _inner.addLocalMedia(
        mediaPath,
        transcriptPath: transcriptPath,
        title: title,
        language: language,
        durationMs: durationMs,
      );

  @override
  Future<Episode?> attachTranscript(
          String episodeId, String transcriptPath) =>
      _inner.attachTranscript(episodeId, transcriptPath);

  @override
  Future<void> removeLocalMedia(String episodeId) =>
      _inner.removeLocalMedia(episodeId);
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/episode.dart';
import '../../../pal/audio_download_service.dart';
import '../../../pal/pal_providers.dart';

/// Per-URL download snapshots for the whole app. The map is populated lazily
/// via [DownloadsController.loadFor] (episode sheets) and kept live by the
/// platform-pushed progress events (including caching triggered by
/// playback itself).
final downloadsControllerProvider = StateNotifierProvider<DownloadsController,
    Map<String, EpisodeDownload>>((ref) {
  final controller =
      DownloadsController(ref.watch(audioDownloadServiceProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

class DownloadsController extends StateNotifier<Map<String, EpisodeDownload>> {
  DownloadsController(this._service) : super(const {}) {
    _subscription = _service.events.listen((event) {
      state = {...state, event.url: event.download};
    });
  }

  final AudioDownloadService _service;
  StreamSubscription<DownloadProgressEvent>? _subscription;

  bool get supported => _service.supported;

  EpisodeDownload? statusOf(String url) => state[url];

  /// Fetch snapshots for the remote URLs of [episodes] not yet known.
  Future<void> loadFor(List<Episode> episodes) async {
    final urls = episodes
        .where((e) => !e.isLocal && e.audioUrl.isNotEmpty)
        .map((e) => e.audioUrl)
        .where((u) => !state.containsKey(u))
        .toList();
    if (urls.isEmpty) return;
    final statuses = await _service.statuses(urls);
    state = {
      ...state,
      for (var i = 0; i < urls.length; i++) urls[i]: statuses[i],
    };
  }

  Future<void> start(String url) => _service.start(url);

  Future<void> delete(String url) async {
    await _service.delete(url);
    // A completed episode has no download worker, so the platform pushes
    // no follow-up event; update locally to keep the UI in sync.
    state = {...state, url: const EpisodeDownload()};
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

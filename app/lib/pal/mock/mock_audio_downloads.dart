import 'dart:async';

import '../audio_download_service.dart';

/// In-memory implementation (desktop/tests, OHOS fallback). Simulates a
/// short download with periodic progress events. No real files involved.
class MockAudioDownloads implements AudioDownloadService {
  final _items = <String, EpisodeDownload>{};
  final _timers = <String, Timer>{};
  final _controller =
      StreamController<DownloadProgressEvent>.broadcast();

  @override
  Stream<DownloadProgressEvent> get events => _controller.stream;

  @override
  bool get supported => true;

  @override
  Future<List<EpisodeDownload>> statuses(List<String> urls) async =>
      urls.map((u) => _items[u] ?? const EpisodeDownload()).toList();

  @override
  Future<void> start(String url) async {
    final current = _items[url];
    if (current != null &&
        (current.state == EpisodeDownloadState.downloading ||
            current.state == EpisodeDownloadState.downloaded)) {
      return;
    }
    const total = 10 * 1024 * 1024;
    var cached = current?.cachedBytes ?? 0;
    _items[url] = const EpisodeDownload(
      state: EpisodeDownloadState.downloading,
      totalBytes: total,
    );
    _emit(url);
    _timers[url]?.cancel();
    _timers[url] = Timer.periodic(const Duration(milliseconds: 100), (t) {
      cached += total ~/ 10;
      if (cached >= total) {
        cached = total;
        t.cancel();
        _timers.remove(url);
        _items[url] = const EpisodeDownload(
          state: EpisodeDownloadState.downloaded,
          cachedBytes: total,
          totalBytes: total,
        );
      } else {
        _items[url] = EpisodeDownload(
          state: EpisodeDownloadState.downloading,
          cachedBytes: cached,
          totalBytes: total,
        );
      }
      _emit(url);
    });
  }

  @override
  Future<void> delete(String url) async {
    _timers.remove(url)?.cancel();
    _items.remove(url);
    _controller.add(DownloadProgressEvent(
      url: url,
      download: const EpisodeDownload(),
    ));
  }

  void _emit(String url) {
    _controller.add(DownloadProgressEvent(
      url: url,
      download: _items[url] ?? const EpisodeDownload(),
    ));
  }
}

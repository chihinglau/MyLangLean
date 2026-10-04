import 'package:flutter/foundation.dart';

/// Download lifecycle state for a single remote episode.
enum EpisodeDownloadState { none, downloading, downloaded, failed }

@immutable
class EpisodeDownload {
  const EpisodeDownload({
    this.state = EpisodeDownloadState.none,
    this.cachedBytes = 0,
    this.totalBytes = -1,
  });

  final EpisodeDownloadState state;
  final int cachedBytes;
  final int totalBytes;

  /// 0..1 when the total length is known, null otherwise.
  double? get fraction =>
      totalBytes > 0 ? (cachedBytes / totalBytes).clamp(0, 1) : null;

  static EpisodeDownloadState parseState(String raw) {
    switch (raw) {
      case 'downloading':
        return EpisodeDownloadState.downloading;
      case 'downloaded':
        return EpisodeDownloadState.downloaded;
      case 'failed':
        return EpisodeDownloadState.failed;
      default:
        return EpisodeDownloadState.none;
    }
  }

  static EpisodeDownload fromMap(Map<dynamic, dynamic> m) => EpisodeDownload(
        state: parseState(m['state'] as String? ?? 'none'),
        cachedBytes: (m['cached'] as num?)?.toInt() ?? 0,
        totalBytes: (m['total'] as num?)?.toInt() ?? -1,
      );
}

/// Event pushed from the platform while a download is running.
@immutable
class DownloadProgressEvent {
  const DownloadProgressEvent({
    required this.url,
    required this.download,
  });

  final String url;
  final EpisodeDownload download;
}

/// PAL: explicit audio download management (independent of playback).
abstract class AudioDownloadService {
  /// Snapshots for [urls] in the same order.
  Future<List<EpisodeDownload>> statuses(List<String> urls);

  /// Begin (or ensure) the download for [url].
  Future<void> start(String url);

  /// Remove the cached episode / abort an in-progress download.
  Future<void> delete(String url);

  /// Pushed progress/state events.
  Stream<DownloadProgressEvent> get events;

  /// Whether explicit downloads are implemented on this platform.
  bool get supported => true;
}

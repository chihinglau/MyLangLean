import 'dart:async';

import 'package:flutter/services.dart';

import '../audio_download_service.dart';

/// Android: backed by the native AudioCacheProxy via MethodChannel
/// ml/audio_downloads (stream-and-cache HTTP proxy, filesDir/audio-cache).
class AndroidAudioDownloads implements AudioDownloadService {
  AndroidAudioDownloads() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onProgress') return;
      final m = call.arguments as Map<dynamic, dynamic>;
      final url = m['url'] as String?;
      if (url == null) return;
      _controller.add(
        DownloadProgressEvent(url: url, download: EpisodeDownload.fromMap(m)),
      );
    });
  }

  static const _channel = MethodChannel('ml/audio_downloads');
  final _controller =
      StreamController<DownloadProgressEvent>.broadcast();

  @override
  Stream<DownloadProgressEvent> get events => _controller.stream;

  @override
  bool get supported => true;

  @override
  Future<List<EpisodeDownload>> statuses(List<String> urls) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'statuses',
      {'urls': urls},
    );
    return (raw ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map(EpisodeDownload.fromMap)
        .toList();
  }

  @override
  Future<void> start(String url) =>
      _channel.invokeMethod<void>('start', {'url': url});

  @override
  Future<void> delete(String url) =>
      _channel.invokeMethod<void>('delete', {'url': url});
}

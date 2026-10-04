import 'dart:async';

import '../audio_download_service.dart';

/// OHOS: explicit audio downloads are not wired yet (no native cache proxy
/// on the AVPlayer side). Reports nothing, accepts no commands; the UI
/// hides the download affordance when [supported] is false.
class OhosAudioDownloads implements AudioDownloadService {
  final _controller =
      StreamController<DownloadProgressEvent>.broadcast();

  @override
  bool get supported => false;

  @override
  Stream<DownloadProgressEvent> get events => _controller.stream;

  @override
  Future<List<EpisodeDownload>> statuses(List<String> urls) async =>
      List.filled(urls.length, const EpisodeDownload());

  @override
  Future<void> start(String url) async {}

  @override
  Future<void> delete(String url) async {}
}

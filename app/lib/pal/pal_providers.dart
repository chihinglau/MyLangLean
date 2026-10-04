import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_player_service.dart';
import 'audio_recorder_service.dart';
import 'audio_download_service.dart';
import 'media_picker_service.dart';
import 'mock/mock_audio_player.dart';
import 'mock/mock_audio_recorder.dart';
import 'mock/mock_media_picker.dart';
import 'mock/mock_audio_downloads.dart';
import 'android/android_audio_player.dart';
import 'android/android_audio_recorder.dart';
import 'android/android_media_picker.dart';
import 'android/android_audio_downloads.dart';
import 'ohos/ohos_audio_player.dart';
import 'ohos/ohos_audio_recorder.dart';
import 'ohos/ohos_media_picker.dart';
import 'ohos/ohos_audio_downloads.dart';
import 'platform_info.dart';

/// PAL wiring. Business code depends ONLY on the abstract services;
/// platform selection happens once, here. Adding iOS later means adding an
/// `else if (isIOS)` branch - no feature code changes.

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  throw UnimplementedError(
      'audioPlayerServiceProvider must be overridden in main()');
});

final audioRecorderServiceProvider = Provider<AudioRecorderService>((ref) {
  throw UnimplementedError(
      'audioRecorderServiceProvider must be overridden in main()');
});

final mediaPickerServiceProvider = Provider<MediaPickerService>((ref) {
  throw UnimplementedError(
      'mediaPickerServiceProvider must be overridden in main()');
});

final audioDownloadServiceProvider = Provider<AudioDownloadService>((ref) {
  throw UnimplementedError(
      'audioDownloadServiceProvider must be overridden in main()');
});

AudioPlayerService createPlatformAudioPlayer() {
  if (isOhos) return OhosAudioPlayer();
  if (isAndroid) return AndroidAudioPlayer();
  return MockAudioPlayer();
}

AudioRecorderService createPlatformAudioRecorder() {
  if (isOhos) return OhosAudioRecorder();
  if (isAndroid) return AndroidAudioRecorder();
  return MockAudioRecorder();
}

MediaPickerService createPlatformMediaPicker() {
  if (isOhos) return OhosMediaPicker();
  if (isAndroid) return AndroidMediaPicker();
  return MockMediaPicker();
}

AudioDownloadService createPlatformAudioDownloads() {
  if (isOhos) return OhosAudioDownloads();
  if (isAndroid) return AndroidAudioDownloads();
  return MockAudioDownloads();
}

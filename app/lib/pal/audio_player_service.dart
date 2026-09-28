import 'dart:async';

/// Platform-agnostic audio playback contract.
///
/// Implementations:
///  * HarmonyOS -> MethodChannel `ml/audio_player` backed by AVPlayer +
///    AVSession (background / lock-screen controls).
///  * iOS (future) -> AVPlayer via official plugin or Swift channel.
///  * Development -> [MockAudioPlayer] virtual clock (no real audio needed).
abstract interface class AudioPlayerService {
  /// High-frequency position ticks (~20-30Hz) for karaoke highlight.
  Stream<Duration> get positionStream;

  /// Emits whenever play/pause state changes.
  Stream<bool> get playingStream;

  /// Emits a human-readable message when the media itself fails to load or
  /// decode (missing file, unsupported codec). Never emits on subtitle
  /// problems. Implementations without real decoding may emit nothing.
  Stream<String> get errorStream;

  Duration get position;
  Duration get duration;
  bool get isPlaying;
  double get rate;

  Future<void> load(String source, {required bool isLocal});
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setRate(double rate);

  /// A/B repeat between [a] and [b]; null clears the loop.
  Future<void> setLoopSegment({Duration? a, Duration? b});

  Future<void> dispose();
}

import 'dart:async';

import '../audio_player_service.dart';

/// Virtual-clock player for UI development on machines without a device.
/// No real audio is played; position advances by wall-clock * rate and the
/// A/B loop is honored exactly like the native AVPlayer implementation.
class MockAudioPlayer implements AudioPlayerService {
  MockAudioPlayer();

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  Timer? _ticker;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 20);
  bool _playing = false;
  double _rate = 1.0;
  Duration? _loopA;
  Duration? _loopB;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<bool> get playingStream => _playingCtrl.stream;
  @override
  Stream<String> get errorStream => const Stream<String>.empty();
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get isPlaying => _playing;
  @override
  double get rate => _rate;

  @override
  Future<void> load(String source, {required bool isLocal}) async {
    await pause();
    _position = Duration.zero;
    _loopA = null;
    _loopB = null;
    _positionCtrl.add(_position);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _playingCtrl.add(true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      var next = _position +
          Duration(milliseconds: (50 * _rate).round());
      final b = _loopB;
      final a = _loopA;
      if (b != null && a != null && next >= b) {
        next = a;
      } else if (next >= _duration) {
        next = _duration;
        _playing = false;
        _ticker?.cancel();
        _playingCtrl.add(false);
      }
      _position = next;
      _positionCtrl.add(_position);
    });
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _ticker?.cancel();
    _playingCtrl.add(false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
    _positionCtrl.add(_position);
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
  }

  @override
  Future<void> setLoopSegment({Duration? a, Duration? b}) async {
    _loopA = a;
    _loopB = b;
  }

  /// Test helper: pretend the media has a given duration.
  set debugDuration(Duration d) => _duration = d;

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    await _positionCtrl.close();
    await _playingCtrl.close();
  }
}

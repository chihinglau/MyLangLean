import 'dart:async';

import 'package:flutter/services.dart';

import '../audio_player_service.dart';

/// Android implementation: MethodChannel `ml/audio_player`.
/// The Kotlin side wraps MediaPlayer (+ A/B loop and speed handling) and
/// emits position ticks over the same protocol as the HarmonyOS side.
class AndroidAudioPlayer implements AudioPlayerService {
  AndroidAudioPlayer() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPosition':
          final ms = (call.arguments as num).toInt();
          _position = Duration(milliseconds: ms);
          _positionCtrl.add(_position);
        case 'onState':
          final state = call.arguments as String?;
          if (state != null && state.startsWith('error:')) {
            _playing = false;
            _playingCtrl.add(false);
            _errorCtrl.add(state.substring('error:'.length).trim());
          } else {
            _playing = state == 'playing';
            _playingCtrl.add(_playing);
          }
        case 'onDuration':
          final ms = (call.arguments as num).toInt();
          _duration = Duration(milliseconds: ms);
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel('ml/audio_player');

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<String> _errorCtrl =
      StreamController<String>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _rate = 1.0;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<bool> get playingStream => _playingCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get isPlaying => _playing;
  @override
  double get rate => _rate;

  @override
  Future<void> load(String source, {required bool isLocal}) =>
      _channel.invokeMethod('load', <String, dynamic>{
        'source': source,
        'isLocal': isLocal,
      });

  @override
  Future<void> play() => _channel.invokeMethod('play');

  @override
  Future<void> pause() => _channel.invokeMethod('pause');

  @override
  Future<void> seekTo(Duration position) =>
      _channel.invokeMethod('seek', <String, int>{
        'ms': position.inMilliseconds,
      });

  @override
  Future<void> setRate(double rate) {
    _rate = rate;
    return _channel.invokeMethod('setRate', <String, double>{
      'rate': rate,
    });
  }

  @override
  Future<void> setLoopSegment({Duration? a, Duration? b}) =>
      _channel.invokeMethod('setLoop', <String, int?>{
        'a': a?.inMilliseconds,
        'b': b?.inMilliseconds,
      });

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
    await _positionCtrl.close();
    await _playingCtrl.close();
    await _errorCtrl.close();
  }
}

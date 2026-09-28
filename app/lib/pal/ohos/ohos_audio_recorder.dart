import 'package:flutter/services.dart';

import '../audio_recorder_service.dart';

/// HarmonyOS implementation: MethodChannel `ml/audio_recorder`.
/// ArkTS side wraps AVRecorder (AAC/m4a) and requests ohos.permission.MICROPHONE.
class OhosAudioRecorder implements AudioRecorderService {
  static const MethodChannel _channel = MethodChannel('ml/audio_recorder');

  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> requestPermission() async {
    final granted =
        await _channel.invokeMethod<bool>('requestPermission') ?? false;
    return granted;
  }

  @override
  Future<void> start() async {
    await _channel.invokeMethod('start');
    _recording = true;
  }

  @override
  Future<String> stop() async {
    final path = await _channel.invokeMethod<String>('stop') ?? '';
    _recording = false;
    return path;
  }
}

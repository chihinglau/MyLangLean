import '../audio_recorder_service.dart';

/// Stub recorder used on development machines without a microphone binding.
class MockAudioRecorder implements AudioRecorderService {
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start() async {
    _recording = true;
  }

  @override
  Future<String> stop() async {
    _recording = false;
    // The UI treats this as an unsaved placeholder; never uploaded.
    return 'mock://recording-${DateTime.now().millisecondsSinceEpoch}.m4a';
  }
}

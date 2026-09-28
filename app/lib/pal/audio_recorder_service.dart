/// Microphone recording contract (AVRecorder on HarmonyOS, AVAudioRecorder
/// on iOS in the future).
abstract interface class AudioRecorderService {
  bool get isRecording;

  /// Starts recording; resolves once the mic is live.
  Future<void> start();

  /// Stops and returns the sandbox file path of the recording (m4a/aac).
  Future<String> stop();

  /// Requests MICROPHONE permission up-front (user_grant on HarmonyOS).
  Future<bool> requestPermission();
}

/// Result of a system media-picker selection. The native side is responsible
/// for copying the picked uri into the app sandbox (HarmonyOS picker uris are
/// temporary).
class PickedMedia {
  const PickedMedia({
    required this.path,
    required this.title,
    this.durationMs = 0,
    this.sizeBytes = 0,
  });

  final String path;
  final String title;
  final int durationMs;
  final int sizeBytes;
}

/// User picked a file whose extension is not in the requested allow-list.
class PickerFileException implements Exception {
  PickerFileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// System file/audio picker contract.
abstract interface class MediaPickerService {
  /// Pick one audio/video file. Returns null when user cancels.
  Future<PickedMedia?> pickAudio();

  /// Pick one arbitrary file (native copy into app sandbox). When [exts] is
  /// non-empty the picked file must match one of them (lower-case, no dot).
  /// Returns null when user cancels.
  Future<PickedMedia?> pickFile({List<String> exts = const []});

  /// Absolute app-private files directory (for persistence indexes).
  Future<String?> filesDir();
}

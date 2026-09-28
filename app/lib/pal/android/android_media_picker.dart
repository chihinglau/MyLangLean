import 'package:flutter/services.dart';

import '../media_picker_service.dart';

/// Android implementation: system file picker (Storage Access Framework)
/// via MethodChannel `ml/media_picker`. Kotlin copies the picked uri into
/// filesDir/imports so the path stays valid.
class AndroidMediaPicker implements MediaPickerService {
  static const MethodChannel _channel = MethodChannel('ml/media_picker');

  @override
  Future<PickedMedia?> pickAudio() => _pick('pickAudio', const []);

  @override
  Future<PickedMedia?> pickFile({List<String> exts = const []}) =>
      _pick('pickFile', exts);

  Future<PickedMedia?> _pick(String method, List<String> exts) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      method,
      <String, dynamic>{'exts': exts},
    );
    if (result == null) return null;
    final path = result['path'] as String;
    if (exts.isNotEmpty) {
      final dot = path.lastIndexOf('.');
      final ext = (dot < 0 ? '' : path.substring(dot + 1)).toLowerCase();
      if (!exts.contains(ext)) {
        throw PickerFileException('请选择 ${exts.join('/')} 格式的文件');
      }
    }
    return PickedMedia(
      path: path,
      title: result['title'] as String? ?? '本地文件',
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
      sizeBytes: (result['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<String?> filesDir() => _channel.invokeMethod<String>('filesDir');
}

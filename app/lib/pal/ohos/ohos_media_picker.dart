import 'dart:io';

import 'package:flutter/services.dart';

import '../media_picker_service.dart';

/// HarmonyOS implementation: system AudioViewPicker via
/// MethodChannel `ml/media_picker`. ArkTS copies the temporary picker uri
/// into the app sandbox and returns the permanent path.
class OhosMediaPicker implements MediaPickerService {
  static const MethodChannel _channel = MethodChannel('ml/media_picker');

  @override
  Future<PickedMedia?> pickAudio() async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>('pickAudio');
    if (result == null) return null;
    return PickedMedia(
      path: result['path'] as String,
      title: result['title'] as String? ?? '本地音频',
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<PickedMedia?> pickFile({List<String> exts = const []}) {
    throw UnimplementedError('HarmonyOS sidecar import is not supported yet');
  }

  @override
  Future<String?> filesDir() async => Directory.systemTemp.path;
}

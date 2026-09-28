import 'dart:io';

import '../media_picker_service.dart';

/// No-op picker on development machines.
class MockMediaPicker implements MediaPickerService {
  @override
  Future<PickedMedia?> pickAudio() async => null;

  @override
  Future<PickedMedia?> pickFile({List<String> exts = const []}) async => null;

  @override
  Future<String?> filesDir() async => Directory.systemTemp.path;
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local_library_store.dart';
import 'data/providers.dart';
import 'data/repositories/persistent_library_repository.dart';
import 'pal/pal_providers.dart';
import 'pal/platform_info.dart';

/// Entry point shared by HarmonyOS HAP and the Android build.
///
/// Platform services are injected as ProviderScope overrides so that no
/// feature code imports platform plugins directly:
///   * on Android  -> Android* MethodChannel implementations + persistent
///                    local library (filesDir/library_index.json)
///   * on HarmonyOS-> Ohos* MethodChannel implementations
///   * otherwise   -> Mock* implementations (desktop UI development)
///   * iOS port later -> add Ios* implementations and one more branch
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final picker = createPlatformMediaPicker();
  final overrides = <Override>[
    audioPlayerServiceProvider
        .overrideWithValue(createPlatformAudioPlayer()),
    audioRecorderServiceProvider
        .overrideWithValue(createPlatformAudioRecorder()),
    mediaPickerServiceProvider.overrideWithValue(picker),
  ];

  if (isAndroid) {
    final dirPath = await picker.filesDir();
    if (dirPath != null) {
      final store = await LocalLibraryStore.open(Directory(dirPath));
      overrides.add(libraryRepositoryProvider
          .overrideWithValue(PersistentLibraryRepository(store)));
    }
  }

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const MyLangLeanApp(),
    ),
  );
}

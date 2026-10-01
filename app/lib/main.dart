import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/kv_store.dart';
import 'data/local_library_store.dart';
import 'data/practice_store.dart';
import 'data/providers.dart';
import 'data/remote/ml_api.dart';
import 'data/repositories/fallback_catalog_repository.dart';
import 'data/repositories/persistent_library_repository.dart';
import 'data/repositories/persistent_practice_repository.dart';
import 'data/repositories/synced_auth_repository.dart';
import 'data/repositories/synced_library_repository.dart';
import 'pal/pal_providers.dart';

/// Entry point shared by HarmonyOS HAP and the Android build.
///
/// Platform services are injected as ProviderScope overrides so that no
/// feature code imports platform plugins directly:
///   * on Android  -> Android* MethodChannel implementations + JSON-backed
///                    persistence (library_index / recordings_index / prefs)
///   * on HarmonyOS-> Ohos* MethodChannel implementations
///   * otherwise   -> Mock* implementations (desktop UI development)
///   * iOS port later -> add Ios* implementations and one more branch
///
/// With persistence available the repositories are additionally wrapped with
/// online implementations: discover catalog loads from the PC service with
/// cache/bundled fallback, accounts authenticate via JWT and subscriptions
/// sync per account.
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

  // JSON persistence lives in the app-private files directory. When the
  // directory is unavailable (e.g. platform stubs) the in-memory defaults
  // are kept, so the app still boots.
  final dirPath = await picker.filesDir();
  if (dirPath != null) {
    final dir = Directory(dirPath);
    final kv = await KvStore.open(dir);
    final libraryStore = await LocalLibraryStore.open(dir);
    final practiceStore = await PracticeStore.open(dir);

    // One dio client for the whole app; its base URL is operator-editable.
    final api = MlApi(
      baseUrl: kv.getString('api.base_url') ?? Env.apiBaseUrl,
    );

    final authRepo = SyncedAuthRepository(kv, api);
    final libraryRepo = SyncedLibraryRepository(
      PersistentLibraryRepository(libraryStore, kv),
      api,
      kv,
    );

    overrides
      ..add(kvStoreProvider.overrideWithValue(kv))
      ..add(serverBaseUrlProvider.overrideWith((ref) => api.baseUrl))
      ..add(mlApiProvider.overrideWithValue(api))
      ..add(catalogRepositoryProvider
          .overrideWithValue(FallbackCatalogRepository(api, kv)))
      ..add(libraryRepositoryProvider.overrideWithValue(libraryRepo))
      ..add(practiceRepositoryProvider
          .overrideWithValue(PersistentPracticeRepository(practiceStore)))
      ..add(authRepositoryProvider.overrideWithValue(authRepo))
      ..add(preferencesProvider
          .overrideWith((ref) => PreferencesNotifier(kv)))
      ..add(recentSearchesProvider
          .overrideWith((ref) => RecentSearchesNotifier(kv)));

    // Bring up the session + subscription mirror without delaying first
    // frame; errors are swallowed inside the repositories.
    unawaited(authRepo.ensureSession().then((_) async {
      await libraryRepo.syncSubscriptions();
    }).catchError((Object _) {}));
  }

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const MyLangLeanApp(),
    ),
  );
}

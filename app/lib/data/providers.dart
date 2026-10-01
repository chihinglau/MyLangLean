import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../domain/entities/episode.dart';
import '../domain/entities/podcast.dart';
import '../domain/entities/user_preferences.dart';
import '../domain/repositories/repositories.dart';
import 'kv_store.dart';
import 'remote/ml_api.dart';
import 'repositories/mock_repositories.dart';

/// JSON KV store; overridden with a real store in `main.dart` (null in
/// widget tests keeps the in-memory defaults).
final kvStoreProvider = Provider<KvStore?>((ref) => null);

/// PC service base URL. Persisted under `api.base_url`; the profile page can
/// change it at runtime.
final serverBaseUrlProvider =
    StateProvider<String>((ref) => Env.apiBaseUrl);

/// Single long-lived dio client. Overridden in `main.dart` with the persisted
/// base URL; tests keep a default instance pointing at Env.apiBaseUrl.
final mlApiProvider = Provider<MlApi>(
  (ref) => MlApi(baseUrl: ref.watch(serverBaseUrlProvider)),
);

/// MVP wires mock/offline implementations. Swap these overrides with remote
/// implementations (dio + FastAPI) without touching feature code.
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => MockCatalogRepository(),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => MockLibraryRepository(),
);

final transcriptRepositoryProvider = Provider<TranscriptRepository>(
  (ref) => LocalAwareTranscriptRepository(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(),
);

final practiceRepositoryProvider = Provider<PracticeRepository>(
  (ref) => MemoryPracticeRepository(),
);

/// Bumped whenever imported media / subscriptions change so pages can
/// rebuild (repositories are wrapped once at startup).
final libraryRefreshProvider = StateProvider<int>((ref) => 0);

/// Bumped after the async startup session check resolves (login, guest
/// downgrade, logout) so account-dependent pages rebuild.
final accountRefreshProvider = StateProvider<int>((ref) => 0);

/// Bumped whenever a recording is saved/deleted/cleared.
final practiceRefreshProvider = StateProvider<int>((ref) => 0);

/// Discover filter state.
class DiscoverFilter {
  const DiscoverFilter({this.query = '', this.level, this.language});
  final String query;
  final ContentLevel? level;
  final String? language;

  DiscoverFilter copyWith({String? query, ContentLevel? level, String? language,
      bool clearLevel = false, bool clearLanguage = false}) =>
      DiscoverFilter(
        query: query ?? this.query,
        level: clearLevel ? null : (level ?? this.level),
        language: clearLanguage ? null : (language ?? this.language),
      );
}

final discoverFilterProvider =
    StateProvider<DiscoverFilter>((ref) => const DiscoverFilter());

/// Language choices offered on the discover page (code, label).
const discoverLanguages = <String, String>{
  'en': '英语',
  'ja': '日语',
  'fr': '法语',
  'de': '德语',
  'es': '西语',
  'ko': '韩语',
  'zh': '中文',
};

final discoverResultsProvider = FutureProvider.autoDispose<List<Podcast>>(
  (ref) async {
    final filter = ref.watch(discoverFilterProvider);
    final repo = ref.watch(catalogRepositoryProvider);
    final matches = filter.query.isNotEmpty
        ? await repo.search(filter.query)
        : await repo.featured();
    // Level/language chips narrow both featured and keyword results.
    return matches
        .where((p) =>
            filter.level == null ||
            filter.level == ContentLevel.all ||
            p.level == filter.level)
        .where((p) =>
            filter.language == null || filter.language!.isEmpty ||
            p.language == filter.language)
        .toList();
  },
);

final podcastEpisodesProvider =
    FutureProvider.autoDispose.family<List<Episode>, Podcast>(
  (ref, podcast) =>
      ref.watch(catalogRepositoryProvider).episodesOf(podcast),
);

/// Learning preferences (playback defaults). Backed by [KvStore] in
/// production; null store keeps an in-memory session for widget tests.
class PreferencesNotifier extends StateNotifier<UserPreferences> {
  PreferencesNotifier(this._kv) : super(_load(_kv));

  final KvStore? _kv;
  static const _key = 'preferences';

  static UserPreferences _load(KvStore? kv) {
    final raw = kv?.get(_key);
    return raw is Map<String, dynamic>
        ? UserPreferences.fromJson(raw)
        : const UserPreferences();
  }

  Future<void> setDefaultRate(double rate) =>
      _update(state.copyWith(defaultRate: rate));

  Future<void> setDefaultFontScale(double scale) =>
      _update(state.copyWith(defaultFontScale: scale));

  Future<void> setSubtitle(SubtitlePref pref) =>
      _update(state.copyWith(subtitle: pref));

  Future<void> _update(UserPreferences next) async {
    state = next;
    await _kv?.set(_key, next.toJson());
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesNotifier, UserPreferences>(
  (ref) => PreferencesNotifier(null),
);

/// Recent discover searches, newest first, persisted in [KvStore].
class RecentSearchesNotifier extends StateNotifier<List<String>> {
  RecentSearchesNotifier(this._kv) : super(_kv?.getStringList(_key) ?? const []);

  final KvStore? _kv;
  static const _key = 'recent_searches';
  static const _max = 10;

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state = [q, ...state.where((e) => e != q)].take(_max).toList();
    await _kv?.set(_key, state);
  }

  Future<void> clear() async {
    state = const [];
    await _kv?.set(_key, const <String>[]);
  }
}

final recentSearchesProvider =
    StateNotifierProvider<RecentSearchesNotifier, List<String>>(
  (ref) => RecentSearchesNotifier(null),
);

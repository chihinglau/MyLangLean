import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/episode.dart';
import '../domain/entities/podcast.dart';
import '../domain/repositories/repositories.dart';
import 'repositories/mock_repositories.dart';

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

final discoverResultsProvider = FutureProvider.autoDispose<List<Podcast>>(
  (ref) async {
    final filter = ref.watch(discoverFilterProvider);
    final repo = ref.watch(catalogRepositoryProvider);
    if (filter.query.isNotEmpty) return repo.search(filter.query);
    return repo.featured(level: filter.level, language: filter.language);
  },
);

final podcastEpisodesProvider =
    FutureProvider.autoDispose.family<List<Episode>, Podcast>(
  (ref, podcast) =>
      ref.watch(catalogRepositoryProvider).episodesOf(podcast),
);

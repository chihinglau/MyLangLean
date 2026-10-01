import '../entities/episode.dart';
import '../entities/podcast.dart';
import '../entities/quota.dart';
import '../entities/recording.dart';
import '../entities/transcript.dart';

/// F1 discover podcasts / episodes.
abstract interface class CatalogRepository {
  Future<List<Podcast>> featured({ContentLevel? level, String? language});
  Future<List<Podcast>> search(String keyword);
  Future<List<Episode>> episodesOf(Podcast podcast);
}

/// F2 subscriptions + local media library.
abstract interface class LibraryRepository {
  List<Podcast> subscriptions();
  Future<void> toggleSubscription(Podcast podcast);
  List<Episode> localMedia();
  Future<Episode> addLocalMedia(
    String mediaPath, {
    String? transcriptPath,
    String? title,
    String? language,
    int? durationMs,
  });

  /// Pair/replace the sidecar transcript of an imported item.
  Future<Episode?> attachTranscript(String episodeId, String transcriptPath);

  /// Remove an imported item (best-effort file deletion included).
  Future<void> removeLocalMedia(String episodeId);
}

/// F3 transcript provider (server ASR / bundled cache).
/// Returns null when the media has no paired transcript.
abstract interface class TranscriptRepository {
  Future<Transcript?> transcriptFor(Episode episode);
}

/// F6 account & quota.
abstract interface class AuthRepository {
  Account current();
  UserQuota quota();
  Future<Account> loginAsGuest();
  Future<Account> login({required String email, required String password});

  /// Registers a new account. Falls back to local-only behaviour on offline
  /// implementations.
  Future<Account> register({
    required String email,
    required String password,
    String? name,
  });

  Future<void> logout();
}

/// F7 recordings & practice history.
abstract interface class PracticeRepository {
  List<Recording> recordings();
  Future<Recording> save(Recording recording);
  Future<void> delete(String id);

  /// Remove every record (audio files are deleted best-effort by the
  /// implementation when it owns them).
  Future<void> clear();

  int totalPracticeSec();
}

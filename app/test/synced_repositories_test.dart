import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/kv_store.dart';
import 'package:mylanglean/data/local_library_store.dart';
import 'package:mylanglean/data/remote/ml_api.dart';
import 'package:mylanglean/data/repositories/fallback_catalog_repository.dart';
import 'package:mylanglean/data/repositories/mock_repositories.dart';
import 'package:mylanglean/data/repositories/persistent_library_repository.dart';
import 'package:mylanglean/data/repositories/remote_transcript_repository.dart';
import 'package:mylanglean/data/repositories/synced_auth_repository.dart';
import 'package:mylanglean/data/repositories/synced_library_repository.dart';
import 'package:mylanglean/domain/entities/episode.dart';
import 'package:mylanglean/domain/entities/podcast.dart';

const _p1 = Podcast(
  id: 'p1',
  title: 'Real English Voices',
  feedUrl: 'https://x/1.xml',
  language: 'en',
  level: ContentLevel.beginner,
);
const _p2 = Podcast(
  id: 'p2',
  title: 'Tokyo Street Stories',
  feedUrl: 'https://x/2.xml',
  language: 'ja',
  level: ContentLevel.intermediate,
);
const _p9 = Podcast(
  id: 'p9',
  title: 'E2E 独家英语频道',
  feedUrl: 'https://x/9.xml',
  language: 'en',
  level: ContentLevel.intermediate,
);

/// Fully scripted offline [MlApi]: every method is overridden, so no Dio HTTP
/// call ever happens; configured fields decide success/failure.
class FakeApi extends MlApi {
  FakeApi() : super(baseUrl: 'http://127.0.0.1:8000');

  Object? registerFailure;
  Object? loginFailure;
  Object? guestFailure;
  Object? meFailure;
  AuthSession? sessionToReturn;
  RemoteAccount? accountToReturn;

  List<Podcast> remotePodcasts = const [];
  Object? podcastsFailure;
  List<Episode> remoteEpisodes = const [];
  Object? episodesFailure;

  List<Podcast> remoteSubscriptions = const [];
  Object? subscriptionsFailure;
  Object? mutateFailure;
  final subscribedIds = <String>[];
  final unsubscribedIds = <String>[];

  @override
  Future<AuthSession> register(
          {required String email,
          required String password,
          String? name}) async =>
      _throwOr(registerFailure, sessionToReturn);

  @override
  Future<AuthSession> login(
          {required String email, required String password}) async =>
      _throwOr(loginFailure, sessionToReturn);

  @override
  Future<AuthSession> loginAsGuest(String deviceId) async =>
      _throwOr(guestFailure,
          sessionToReturn ??
              const AuthSession(token: 'guest-jwt', isGuest: true));

  @override
  Future<RemoteAccount> me() async =>
      _throwOr(meFailure, accountToReturn);

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    // Quota refresh is best effort; tests never need its value.
    throw MlApiException('quota not needed in tests', statusCode: 599);
  }

  @override
  Future<List<Podcast>> podcasts(
          {String? q,
          String? language,
          String? level,
          int page = 1,
          int size = 200}) async =>
      _throwOr(podcastsFailure, remotePodcasts);

  @override
  Future<List<Episode>> episodes(String podcastId) async =>
      _throwOr(episodesFailure, remoteEpisodes);

  @override
  Future<List<Podcast>> subscriptions() async =>
      _throwOr(subscriptionsFailure, remoteSubscriptions);

  @override
  Future<void> subscribe(String podcastId) async {
    if (mutateFailure != null) throw mutateFailure!;
    subscribedIds.add(podcastId);
  }

  @override
  Future<void> unsubscribe(String podcastId) async {
    if (mutateFailure != null) throw mutateFailure!;
    unsubscribedIds.add(podcastId);
  }

  T _throwOr<T>(Object? failure, T? value) {
    if (failure != null) throw failure;
    return value as T;
  }
}

Future<KvStore> tempKv() async {
  final dir = await Directory.systemTemp.createTemp('mll-synced-test-');
  addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
  return KvStore.open(dir);
}

/// Scripts the transcription job lifecycle without any real HTTP.
class _FakeTranscriptApi extends FakeApi {
  _FakeTranscriptApi({
    this.terminalStatus = 'done',
    this.errorText,
    this.transcriptJson,
    this.processingPolls = 1,
  });

  String terminalStatus;
  String? errorText;
  Map<String, dynamic>? transcriptJson;
  int processingPolls;
  int createCalls = 0;
  int pollCalls = 0;
  String? lastClientKey;

  @override
  Future<RemoteTranscriptionJob> createTranscription({
    required String audioUrl,
    String language = 'en',
    String? targetLang,
    String? clientKey,
  }) async {
    createCalls++;
    lastClientKey = clientKey;
    return const RemoteTranscriptionJob(id: 'job-9', status: 'queued');
  }

  @override
  Future<RemoteTranscriptionJob> transcriptionJob(String jobId) async {
    pollCalls++;
    if (pollCalls <= processingPolls) {
      return RemoteTranscriptionJob(id: jobId, status: 'processing');
    }
    return RemoteTranscriptionJob(
      id: jobId,
      status: terminalStatus,
      error: errorText,
      transcript: transcriptJson,
    );
  }
}

const _transcriptJson = {
  'version': 1,
  'language': 'de',
  'duration': 2.4,
  'segments': [
    {
      'id': 0,
      'start': 0.1,
      'end': 2.2,
      'text': 'Hello there.',
      'words': [
        {'w': 'Hello', 's': 0.1, 'e': 1.0, 'p': 0.9},
        {'w': 'there.', 's': 1.1, 'e': 2.2, 'p': 0.9},
      ],
    },
  ],
};

const _onlineEpisode = Episode(
  id: 'ep-1',
  title: 'Episode 1',
  audioUrl: 'https://cdn/x.mp3',
  language: 'de',
);

void main() {
  group('SyncedAuthRepository', () {
    test('register persists JWT and account snapshot', () async {
      final kv = await tempKv();
      final api = FakeApi()
        ..sessionToReturn = const AuthSession(
          token: 'user-jwt',
          isGuest: false,
          account: RemoteAccount(
              id: '1', name: 'Bob', email: 'b@x.com', isGuest: false),
        );
      final repo = SyncedAuthRepository(kv, api);

      final account = await repo.register(
          email: 'b@x.com', password: 'secret1', name: 'Bob');
      expect(account.isGuest, isFalse);
      expect(account.email, 'b@x.com');
      expect(account.name, 'Bob');
      expect(repo.current().email, 'b@x.com');
      expect(api.token, 'user-jwt');
      expect(kv.getString('auth.token'), 'user-jwt');
      expect(kv.getBool('auth.isGuest'), isFalse);
    });

    test('register failure keeps the guest state and surfaces message',
        () async {
      final kv = await tempKv();
      final api = FakeApi()
        ..registerFailure = MlApiException('该邮箱已注册，请直接登录',
            statusCode: 409);
      final repo = SyncedAuthRepository(kv, api);

      expect(
        () => repo.register(email: 'b@x.com', password: 'secret1'),
        throwsA(isA<MlApiException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.current().isGuest, isTrue);
      expect(api.token, isNull);
      expect(kv.getString('auth.token'), isNull);
    });

    test('ensureSession logs in as guest when no token exists', () async {
      final kv = await tempKv();
      final api = FakeApi(); // default guest session
      final repo = SyncedAuthRepository(kv, api);

      final account = await repo.ensureSession();
      expect(account.isGuest, isTrue);
      expect(api.token, 'guest-jwt');
      expect(kv.getString('auth.token'), 'guest-jwt');
      // Device id is persisted and stable.
      final deviceId = kv.getString('auth.deviceId');
      expect(deviceId, isNotNull);
      await repo.ensureSession();
      expect(kv.getString('auth.deviceId'), deviceId);
    });

    test('ensureSession degrades to local guest when offline', () async {
      final kv = await tempKv();
      final api = FakeApi()
        ..guestFailure = MlApiException('无法连接服务器');
      final repo = SyncedAuthRepository(kv, api);

      final account = await repo.ensureSession();
      expect(account.isGuest, isTrue);
      expect(api.token, isNull);
    });

    test('expired stored token is dropped and replaced with a guest session',
        () async {
      final kv = await tempKv();
      await kv.set('auth.token', 'old-token');
      final api = FakeApi()
        ..meFailure = MlApiException('登录已过期', statusCode: 401);
      final repo = SyncedAuthRepository(kv, api);

      await repo.ensureSession();
      expect(api.token, 'guest-jwt');
      expect(kv.getString('auth.token'), 'guest-jwt');
    });

    test('disabled account (403) is signed out to guest with a one-shot notice',
        () async {
      final kv = await tempKv();
      await kv.set('auth.token', 'user-token');
      await kv.set('auth.isGuest', false);
      final api = FakeApi()
        ..meFailure =
            MlApiException('账号已被禁用，请联系管理员', statusCode: 403);
      final repo = SyncedAuthRepository(kv, api);

      final account = await repo.ensureSession();
      expect(account.isGuest, isTrue);
      expect(api.token, 'guest-jwt');
      expect(kv.getString('auth.token'), 'guest-jwt');
      expect(await repo.consumeNotice(), '账号已被禁用，请联系管理员');
      // The notice is one-shot.
      expect(await repo.consumeNotice(), isNull);
    });
  });

  group('FallbackCatalogRepository', () {
    test('online result is used and cached for offline reuse', () async {
      final kv = await tempKv();
      final api = FakeApi()..remotePodcasts = const [_p9];
      final repo = FallbackCatalogRepository(api, kv);

      final first = await repo.featured();
      expect(first.map((p) => p.id), ['p9']);
      expect(kv.get('cache.catalog.podcasts'), isNotNull);

      // Second repository on the same cache, now offline.
      final offlineApi = FakeApi()..podcastsFailure = Exception('offline');
      final offlineRepo = FallbackCatalogRepository(offlineApi, kv);
      final cached = await offlineRepo.featured();
      expect(cached.map((p) => p.id), ['p9']);
    });

    test('falls back to the bundled catalog when never synced', () async {
      final kv = await tempKv();
      final api = FakeApi()..podcastsFailure = Exception('offline');
      final repo = FallbackCatalogRepository(api, kv);

      final list = await repo.featured();
      expect(list, hasLength(8));
    });

    test('search offline searches the cache/bundle locally', () async {
      final kv = await tempKv();
      final api = FakeApi()..podcastsFailure = Exception('offline');
      final repo = FallbackCatalogRepository(api, kv);

      final ja = await repo.search('tokyo');
      expect(ja.map((p) => p.id), ['p2']);
    });

    test('remote episodes get absolute URLs and podcast display fields',
        () async {
      final kv = await tempKv();
      final api = FakeApi()
        ..remoteEpisodes = const [
          Episode(
            id: 'p9-e1',
            title: 'E2E 单集',
            audioUrl: '/media/sample.mp3',
            duration: Duration(milliseconds: 17640),
            language: 'en',
          ),
        ];
      final repo = FallbackCatalogRepository(api, kv);

      final episodes = await repo.episodesOf(_p9);
      expect(episodes, hasLength(1));
      expect(episodes.first.audioUrl,
          'http://127.0.0.1:8000/media/sample.mp3');
      expect(episodes.first.podcastTitle, 'E2E 独家英语频道');
      expect(episodes.first.isLocal, isFalse);
      expect(kv.get('cache.catalog.episodes.p9'), isNotNull);
    });

    test('offline bundled podcasts play the asset sample', () async {
      final kv = await tempKv();
      final api = FakeApi()..episodesFailure = Exception('offline');
      final repo = FallbackCatalogRepository(api, kv);

      final episodes = await repo.episodesOf(_p1);
      expect(episodes, hasLength(2));
      expect(episodes.first.playableSource.startsWith('asset://'), isTrue);
    });
  });

  group('SyncedLibraryRepository', () {
    Future<(SyncedLibraryRepository, FakeApi, KvStore)> build() async {
      final kv = await tempKv();
      final dir = await Directory.systemTemp.createTemp('mll-lib-test-');
      addTearDown(
          () => dir.delete(recursive: true).catchError((_) => dir));
      final store = await LocalLibraryStore.open(dir);
      final api = FakeApi()..token = 'jwt';
      final repo =
          SyncedLibraryRepository(PersistentLibraryRepository(store, kv),
              api, kv);
      return (repo, api, kv);
    }

    test('toggle pushes subscribe/unsubscribe and updates local state',
        () async {
      final (repo, api, _) = await build();

      await repo.toggleSubscription(_p1);
      expect(repo.subscriptions().map((p) => p.id), ['p1']);
      expect(api.subscribedIds, ['p1']);

      await repo.toggleSubscription(_p1);
      expect(repo.subscriptions(), isEmpty);
      expect(api.unsubscribedIds, ['p1']);
    });

    test('push failure keeps optimistic state and queues a pending op',
        () async {
      final (_, _, kv) = await build();
      final api2 = FakeApi()
        ..token = 'jwt'
        ..mutateFailure = MlApiException('offline');
      final dir = await Directory.systemTemp.createTemp('mll-lib-dirty-');
      addTearDown(
          () => dir.delete(recursive: true).catchError((_) => dir));
      final store = await LocalLibraryStore.open(dir);
      final dirtyRepo = SyncedLibraryRepository(
          PersistentLibraryRepository(store, kv), api2, kv);

      await dirtyRepo.toggleSubscription(_p1);
      expect(dirtyRepo.subscriptions(), hasLength(1));
      final pending = kv.get('subscriptions.pending') as List<dynamic>?;
      expect(pending, hasLength(1));
      expect(pending!.single['id'], 'p1');
      expect(pending.single['sub'], isTrue);
    });

    test('sync replays a queued subscribe and clears the queue', () async {
      final (_, api, kv) = await build();
      api.mutateFailure = MlApiException('offline');
      // Toggle through a second repo sharing the same kv/store like an app
      // restart would.
      final dir = await Directory.systemTemp.createTemp('mll-lib-replay-');
      addTearDown(
          () => dir.delete(recursive: true).catchError((_) => dir));
      final store = await LocalLibraryStore.open(dir);
      final repo = SyncedLibraryRepository(
          PersistentLibraryRepository(store, kv), api, kv);
      await repo.toggleSubscription(_p1);
      expect(api.subscribedIds, isEmpty);

      // Back online: server already carries p1 once the replay lands.
      api
        ..mutateFailure = null
        ..remoteSubscriptions = const [_p1];
      await repo.syncSubscriptions();

      expect(api.subscribedIds, ['p1']);
      expect(kv.get('subscriptions.pending'), isNull);
      expect(repo.subscriptions().map((p) => p.id), ['p1']);
    });

    test('offline unsubscribe is never resurrected by the server union',
        () async {
      final (repo, api, kv) = await build();
      // Existing server-side subscription.
      await repo.toggleSubscription(_p1);
      api.subscribedIds.clear();
      api.remoteSubscriptions = const [_p1];

      // Network breaks: unsubscribe stays optimistic and pending locally.
      api.mutateFailure = MlApiException('offline');
      await repo.toggleSubscription(_p1);
      expect(repo.subscriptions(), isEmpty);

      // Sync while the server still reports p1: local intent wins, the
      // DELETE stays queued, and p1 must not reappear locally.
      await repo.syncSubscriptions();
      expect(repo.subscriptions(), isEmpty);
      expect(api.unsubscribedIds, isEmpty); // replay failed
      final pending = kv.get('subscriptions.pending') as List<dynamic>;
      expect(pending.single['id'], 'p1');
      expect(pending.single['sub'], isFalse);
    });

    test('pending unsubscribe eventually lands after reconnect', () async {
      final (repo, api, _) = await build();
      await repo.toggleSubscription(_p1);
      api.subscribedIds.clear();
      api.remoteSubscriptions = const [_p1];

      api.mutateFailure = MlApiException('offline');
      await repo.toggleSubscription(_p1);

      api
        ..mutateFailure = null
        ..remoteSubscriptions = const [];
      await repo.syncSubscriptions();

      expect(api.unsubscribedIds, ['p1']);
      expect(repo.subscriptions(), isEmpty);
    });

    test('pending subscribe to a 404 podcast is dropped locally', () async {
      final (repo, api, kv) = await build();
      api.mutateFailure = MlApiException('频道不存在', statusCode: 404);
      await repo.toggleSubscription(_p9);
      expect(repo.subscriptions(), hasLength(1));

      api.remoteSubscriptions = const [];
      await repo.syncSubscriptions();

      expect(repo.subscriptions(), isEmpty);
      expect(api.subscribedIds, isEmpty);
      expect(kv.get('subscriptions.pending'), isNull);
    });

    test('logged-out toggle is queued and replayed once authenticated',
        () async {
      final kv = await tempKv();
      final dir = await Directory.systemTemp.createTemp('mll-lib-guestq-');
      addTearDown(
          () => dir.delete(recursive: true).catchError((_) => dir));
      final store = await LocalLibraryStore.open(dir);
      final api = FakeApi(); // no token yet
      final repo = SyncedLibraryRepository(
          PersistentLibraryRepository(store, kv), api, kv);

      await repo.toggleSubscription(_p1);
      expect(api.subscribedIds, isEmpty);
      expect(repo.subscriptions(), hasLength(1));

      // "Login" happens, next sync flushes the queue.
      api
        ..token = 'jwt'
        ..remoteSubscriptions = const [_p1];
      await repo.syncSubscriptions();
      expect(api.subscribedIds, ['p1']);
      expect(kv.get('subscriptions.pending'), isNull);
    });

    test('sync merges server and local subscriptions and pushes locals up',
        () async {
      final (repo, api, kv) = await build();
      api.remoteSubscriptions = const [_p1];
      // Something subscribed locally (e.g. while offline on this device).
      await repo.toggleSubscription(_p2);
      api.subscribedIds.clear();

      final changed = await repo.syncSubscriptions();
      expect(changed, isTrue);
      final ids = repo.subscriptions().map((p) => p.id).toSet();
      expect(ids, {'p1', 'p2'});
      expect(api.subscribedIds, ['p2']); // local-only item pushed up
      expect(kv.get('subscriptions.pending'), isNull);
    });

    test('sync is a no-op while logged out', () async {
      final kv = await tempKv();
      final dir = await Directory.systemTemp.createTemp('mll-lib-guest-');
      addTearDown(
          () => dir.delete(recursive: true).catchError((_) => dir));
      final store = await LocalLibraryStore.open(dir);
      final api = FakeApi(); // no token
      final repo =
          SyncedLibraryRepository(PersistentLibraryRepository(store, kv),
              api, kv);
      expect(await repo.syncSubscriptions(), isFalse);
    });
  });

  group('RemoteTranscriptRepository', () {
    RemoteTranscriptRepository build(_FakeTranscriptApi api, KvStore kv) =>
        RemoteTranscriptRepository(api,
            kv: kv, pollInterval: Duration.zero);

    test('catalog episode submits ASR, polls, and returns transcript',
        () async {
      final kv = await tempKv();
      final api =
          _FakeTranscriptApi(transcriptJson: _transcriptJson);
      final t = await build(api, kv).transcriptFor(_onlineEpisode);

      expect(t, isNotNull);
      expect(t!.segments, hasLength(1));
      expect(t.segments.first.text, 'Hello there.');
      expect(api.createCalls, 1);
      expect(api.lastClientKey, 'ep-ep-1');
      expect(api.pollCalls, greaterThanOrEqualTo(2));
    });

    test('second call is served from cache (no new transcription)',
        () async {
      final kv = await tempKv();
      final api = _FakeTranscriptApi(transcriptJson: _transcriptJson);
      final repo = build(api, kv);
      await repo.transcriptFor(_onlineEpisode);
      final again = await repo.transcriptFor(_onlineEpisode);

      expect(again!.segments.first.text, 'Hello there.');
      expect(api.createCalls, 1);
    });

    test('KV cache survives a fresh repository instance', () async {
      final kv = await tempKv();
      final api1 = _FakeTranscriptApi(transcriptJson: _transcriptJson);
      await build(api1, kv).transcriptFor(_onlineEpisode);

      final api2 = _FakeTranscriptApi(transcriptJson: _transcriptJson);
      final t = await build(api2, kv).transcriptFor(_onlineEpisode);

      expect(t!.language, 'de');
      expect(api2.createCalls, 0);
    });

    test('quota error surfaces a Chinese TranscriptException', () async {
      final kv = await tempKv();
      final api = _FakeTranscriptApi(
        terminalStatus: 'error',
        errorText: 'monthly quota exhausted: 100 min',
      );
      try {
        await build(api, kv).transcriptFor(_onlineEpisode);
        fail('expected TranscriptException');
      } on TranscriptException catch (e) {
        expect(e.message, contains('额度'));
      }
      expect(api.createCalls, 1);
    });

    test('local imported episode delegates to the local resolver',
        () async {
      final kv = await tempKv();
      final dir = await Directory.systemTemp.createTemp('mll-sidecar-');
      addTearDown(
          () => dir.delete(recursive: true).catchError((_) => dir));
      final sidecar = File(
          '${dir.path}${Platform.pathSeparator}tool_sample.json');
      await sidecar.writeAsString(
          await File('test/fixtures/tool_sample_transcript.json')
              .readAsString());
      final localEpisode = Episode(
        id: 'loc-1',
        title: 'Local',
        audioUrl: sidecar.path,
        isLocal: true,
        transcriptPath: sidecar.path,
      );
      final api = _FakeTranscriptApi(transcriptJson: _transcriptJson);
      final t =
          await RemoteTranscriptRepository(api, kv: kv)
              .transcriptFor(localEpisode);

      expect(t!.segments.first.text, 'Studio export works.');
      expect(api.createCalls, 0);
    });
  });
}

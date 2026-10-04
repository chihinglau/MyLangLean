import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/remote/ml_api.dart';

/// Programmable HTTP adapter so no real socket is opened in tests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  /// Returns (statusCode, jsonBody) per request; throwing a [DioException]
  /// simulates transport failures.
  final Object? Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = handler(options);
    if (result is DioException) throw result;
    final pair = result as (int, Object?);
    final body = pair.$2 == null ? '' : jsonEncode(pair.$2);
    return ResponseBody.fromString(
      body,
      pair.$1,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

MlApi apiWith(Object? Function(RequestOptions) handler) {
  final dio = Dio();
  dio.httpClientAdapter = FakeAdapter(handler);
  return MlApi(baseUrl: 'http://127.0.0.1:8000', dio: dio);
}

void main() {
  group('absoluteUrl', () {
    const base = 'http://127.0.0.1:8000';

    test('joins relative paths', () {
      expect(MlApi.absoluteUrl(base, '/media/sample.mp3'),
          'http://127.0.0.1:8000/media/sample.mp3');
      expect(MlApi.absoluteUrl('$base/', '/media/x.mp3'),
          'http://127.0.0.1:8000/media/x.mp3');
      expect(MlApi.absoluteUrl(base, 'media/y.mp3'),
          'http://127.0.0.1:8000/media/y.mp3');
    });

    test('passes through absolute and special schemes', () {
      expect(MlApi.absoluteUrl(base, 'https://a.com/x.png'),
          'https://a.com/x.png');
      expect(MlApi.absoluteUrl(base, 'asset://assets/a.mp3'),
          'asset://assets/a.mp3');
      expect(MlApi.absoluteUrl(base, ''), '');
      expect(MlApi.absoluteUrl(base, null), '');
    });
  });

  group('auth', () {
    test('register stores the JWT and parses the account', () async {
      final api = apiWith((options) {
        expect(options.path, contains('register'));
        final rawData = options.data;
        final body = rawData is String
            ? jsonDecode(rawData) as Map
            : rawData as Map;
        expect(body['email'], 'a@x.com');
        return (
          200,
          {
            'access_token': 'jwt-123',
            'token_type': 'bearer',
            'is_guest': false,
            'account': {
              'id': '7',
              'email': 'a@x.com',
              'name': 'Alice',
              'is_guest': false,
              'created_at': '2026-10-01T00:00:00'
            }
          }
        );
      });

      final session = await api.register(
          email: 'a@x.com', password: 'secret1', name: 'Alice');
      expect(session.token, 'jwt-123');
      expect(session.isGuest, isFalse);
      expect(session.account?.name, 'Alice');
      expect(api.token, 'jwt-123');
      expect(api.isAuthenticated, isTrue);
    });

    test('wrong password maps to a Chinese 401 message', () async {
      final api = apiWith((_) => (401, {'detail': '邮箱或密码错误'}));
      try {
        await api.login(email: 'a@x.com', password: 'bad');
        fail('expected MlApiException');
      } on MlApiException catch (e) {
        expect(e.statusCode, 401);
        expect(e.friendlyMessage, '邮箱或密码错误');
      }
    });

    test('duplicate registration maps to 409', () async {
      final api = apiWith((_) => (409, {'detail': '邮箱已注册'}));
      try {
        await api.register(email: 'a@x.com', password: 'secret1');
        fail('expected MlApiException');
      } on MlApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.friendlyMessage, contains('已注册'));
      }
    });

    test('connection failure yields a friendly transport message', () async {
      final api = MlApi(baseUrl: 'http://127.0.0.1:8000', dio: Dio()
        ..httpClientAdapter = FakeAdapter((_) =>
            throw DioException(
                type: DioExceptionType.connectionError,
                requestOptions: RequestOptions(path: '/x'))));
      try {
        await api.login(email: 'a@x.com', password: 'bad');
        fail('expected MlApiException');
      } on MlApiException catch (e) {
        expect(e.statusCode, 0);
        expect(e.friendlyMessage, contains('无法连接服务器'));
      }
    });
  });

  group('catalog parsing', () {
    test('podcasts list parses camelCase items', () async {
      final api = apiWith((_) => (
            200,
            {
              'items': [
                {
                  'id': 'p9',
                  'title': 'E2E 独家英语频道',
                  'author': 'QA',
                  'feedUrl': 'https://x/feed.xml',
                  'artworkUrl': '/media/a.png',
                  'language': 'en',
                  'level': 'intermediate',
                  'description': 'only on server',
                  'published': true,
                }
              ],
              'total': 1
            }
          ));
      final list = await api.podcasts(q: 'E2E');
      expect(list, hasLength(1));
      expect(list.first.id, 'p9');
      expect(list.first.title, 'E2E 独家英语频道');
      expect(list.first.artworkUrl,
          'http://127.0.0.1:8000/media/a.png');
    });
  });

  group('transcriptions', () {
    test('create posts audio_url/language/client_key and parses 202',
        () async {
      final api = apiWith((options) {
        expect(options.path, endsWith('/transcriptions'));
        final raw = options.data;
        final body =
            (raw is String ? jsonDecode(raw) : raw) as Map;
        expect(body['audio_url'], 'http://x/a.mp3');
        expect(body['language'], 'de');
        expect(body['client_key'], 'ep-1');
        return (202, {'id': 'job-1', 'status': 'queued'});
      });
      final job = await api.createTranscription(
          audioUrl: 'http://x/a.mp3',
          language: 'de',
          clientKey: 'ep-1');
      expect(job.id, 'job-1');
      expect(job.status, 'queued');
      expect(job.isDone, isFalse);
      expect(job.isError, isFalse);
    });

    test('transcriptionJob parses a done job with transcript json',
        () async {
      final api = apiWith((options) {
        expect(options.path, endsWith('/transcriptions/job-1'));
        return (
          200,
          {
            'id': 'job-1',
            'status': 'done',
            'billed_sec': 18,
            'transcript': {
              'version': 1,
              'language': 'en',
              'duration': 17.6,
              'segments': <dynamic>[],
            },
          }
        );
      });
      final job = await api.transcriptionJob('job-1');
      expect(job.isDone, isTrue);
      expect(job.billedSec, 18);
      expect(job.transcript?['language'], 'en');
    });

    test('transcriptionJob maps an error status', () async {
      final api = apiWith((_) => (
            200,
            {
              'id': 'job-2',
              'status': 'error',
              'error': 'monthly quota exhausted: 100 min',
            }
          ));
      final job = await api.transcriptionJob('job-2');
      expect(job.isError, isTrue);
      expect(job.error, contains('quota'));
    });
  });

  group('ReleaseInfo', () {
    test('parses the snake_case envelope and abs download url', () {
      final info = ReleaseInfo.fromJson({
        'has_update': true,
        'version': '0.4.1',
        'build_no': 5,
        'notes': '修复若干问题',
        'mandatory': true,
        'size': 1048576,
        'sha256': 'abc',
        'url': '/api/v1/releases/download/5',
        'published_at': '2026-10-01T10:00:00',
      }, 'http://127.0.0.1:8000');
      expect(info.hasUpdate, isTrue);
      expect(info.version, '0.4.1');
      expect(info.buildNo, 5);
      expect(info.mandatory, isTrue);
      expect(info.size, 1048576);
      expect(info.url,
          'http://127.0.0.1:8000/api/v1/releases/download/5');
    });

    test('empty release means no update', () {
      final info = ReleaseInfo.fromJson({'has_update': false}, 'http://x');
      expect(info.hasUpdate, isFalse);
    });
  });
}

import 'package:dio/dio.dart';

import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';

/// Network error with an HTTP-ish [statusCode] (0 = transport failure) and a
/// ready-to-show Chinese [friendlyMessage].
class MlApiException implements Exception {
  MlApiException(this.friendlyMessage, {this.statusCode = 0, this.raw});

  final int statusCode;
  final String friendlyMessage;
  final Object? raw;

  @override
  String toString() => friendlyMessage;
}

/// Account information returned by `/auth/*` and `/me`.
class RemoteAccount {
  const RemoteAccount({
    required this.id,
    required this.name,
    this.email,
    required this.isGuest,
    this.createdAt,
  });

  final String id;
  final String? email;
  final String name;
  final bool isGuest;
  final String? createdAt;

  factory RemoteAccount.fromJson(Map<String, dynamic> json) => RemoteAccount(
        id: (json['id'] ?? '').toString(),
        email: json['email'] as String?,
        name: (json['name'] as String?) ?? '',
        isGuest: json['is_guest'] == true || json['isGuest'] == true,
        createdAt: json['created_at'] as String?,
      );
}

/// Result of a successful auth call (JWT + account snapshot).
class AuthSession {
  const AuthSession({
    required this.token,
    required this.isGuest,
    this.account,
  });

  final String token;
  final bool isGuest;
  final RemoteAccount? account;
}

/// OTA release descriptor (`/releases/latest`).
class ReleaseInfo {
  const ReleaseInfo({
    required this.hasUpdate,
    this.id = 0,
    this.version = '',
    this.buildNo = 0,
    this.notes = '',
    this.mandatory = false,
    this.size = 0,
    this.sha256 = '',
    this.url = '',
    this.publishedAt,
  });

  final bool hasUpdate;

  /// Server-side release id (used to isolate OTA download temp files).
  final int id;
  final String version;
  final int buildNo;
  final String notes;
  final bool mandatory;
  final int size;
  final String sha256;

  /// Absolute, ready-to-download URL.
  final String url;
  final String? publishedAt;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json, String baseUrl) =>
      ReleaseInfo(
        hasUpdate: json['has_update'] == true || json['hasUpdate'] == true,
        id: (json['id'] as num?)?.toInt() ?? 0,
        version: (json['version'] ?? json['versionName'] ?? '').toString(),
        buildNo:
            (json['build_no'] ?? json['buildNo'] ?? json['build'] as num?)
                    ?.toInt() ??
                0,
        notes: (json['notes'] ?? json['changelog'] ?? '').toString(),
        mandatory: json['mandatory'] == true || json['forceUpdate'] == true,
        size: (json['size'] as num?)?.toInt() ?? 0,
        sha256: (json['sha256'] ?? '').toString(),
        url: MlApi.absoluteUrl(
            baseUrl, (json['url'] ?? json['downloadUrl'] ?? '').toString()),
        publishedAt: (json['published_at'] ?? json['publishedAt']) as String?,
      );

  static const empty = ReleaseInfo(hasUpdate: false);
}

/// dio-based client for the PC FastAPI service.
///
/// One instance lives for the whole app (wired in `main.dart`). It carries
/// the current JWT in memory; callers persist/restore it via [token] and the
/// KV store. Every failure is normalised to [MlApiException] so the UI can
/// show Chinese messages without knowing dio.
class MlApi {
  MlApi({required String baseUrl, Dio? dio})
      : _dio = dio ?? Dio() {
    this.baseUrl = baseUrl;
    _dio.options
      ..connectTimeout = const Duration(seconds: 5)
      ..receiveTimeout = const Duration(seconds: 10)
      ..headers['Accept'] = 'application/json';
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = token;
        if (t != null && t.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;

  String? token;

  /// Content version of the most recent successful catalog fetch, used to
  /// tag offline snapshots (null before the first successful fetch).
  String? lastCatalogVersion;

  String get baseUrl => _dio.options.baseUrl;
  set baseUrl(String value) {
    var v = value.trim();
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    _dio.options.baseUrl = v;
  }

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  // ---- accounts -----------------------------------------------------------

  Future<AuthSession> register({
    required String email,
    required String password,
    String? name,
  }) =>
      _auth('/api/v1/auth/register', {
        'email': email,
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      });

  Future<AuthSession> login({
    required String email,
    required String password,
  }) =>
      _auth('/api/v1/auth/login', {
        'email': email,
        'password': password,
      });

  Future<AuthSession> loginAsGuest(String deviceId) =>
      _auth('/api/v1/auth/device', {'device_id': deviceId});

  Future<AuthSession> _auth(String path, Map<String, dynamic> body) async {
    final res = await _post(path, data: body);
    final data = res.data as Map<String, dynamic>;
    final jwt = (data['access_token'] ?? '').toString();
    if (jwt.isEmpty) {
      throw MlApiException('服务器返回异常，请稍后重试', raw: data);
    }
    token = jwt;
    final acc = data['account'];
    return AuthSession(
      token: jwt,
      isGuest: data['is_guest'] == true,
      account: acc is Map<String, dynamic>
          ? RemoteAccount.fromJson(acc)
          : null,
    );
  }

  Future<RemoteAccount> me() async {
    final res = await _get('/api/v1/me');
    return RemoteAccount.fromJson(res.data as Map<String, dynamic>);
  }

  // ---- catalog ------------------------------------------------------------

  Future<List<Podcast>> podcasts({
    String? q,
    String? language,
    String? level,
    int page = 1,
    int size = 200,
  }) async {
    final res = await _get('/api/v1/catalog/podcasts', query: {
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (language != null && language.isNotEmpty) 'language': language,
      if (level != null && level.isNotEmpty) 'level': level,
      'page': page,
      'size': size,
    });
    final data = res.data as Map<String, dynamic>;
    final v = data['content_version'];
    if (v != null && v.toString().isNotEmpty) {
      lastCatalogVersion = v.toString();
    }
    final items = (data['items'] as List<dynamic>? ?? const []);
    return items
        .whereType<Map<String, dynamic>>()
        .map(_podcastFromRemote)
        .toList();
  }

  Future<List<Episode>> episodes(String podcastId) async {
    final res =
        await _get('/api/v1/catalog/podcasts/$podcastId/episodes');
    final items = (res.data as List<dynamic>? ?? const []);
    return items
        .whereType<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .toList();
  }

  Podcast _podcastFromRemote(Map<String, dynamic> json) {
    // Make relative media URLs (artwork) directly usable by Image.network.
    if (json['artworkUrl'] is String) {
      json['artworkUrl'] = absoluteUrl(baseUrl, json['artworkUrl'] as String?);
    }
    return Podcast.fromJson(json);
  }

  /// Rewrites a remote episode's relative URLs and fills display fields the
  /// server does not provide (podcast title / artwork).
  Episode hydrateEpisode(Episode raw, Podcast podcast) => Episode(
        id: raw.id,
        title: raw.title,
        podcastId: raw.podcastId ?? podcast.id,
        podcastTitle: podcast.title,
        artworkUrl: podcast.artworkUrl,
        audioUrl: absoluteUrl(baseUrl, raw.audioUrl),
        duration: raw.duration,
        pubDate: raw.pubDate,
        language: raw.language.isNotEmpty ? raw.language : podcast.language,
      );

  // ---- subscriptions ------------------------------------------------------

  Future<List<Podcast>> subscriptions() async {
    final res = await _get('/api/v1/me/subscriptions');
    final items =
        ((res.data as Map<String, dynamic>)['items'] as List<dynamic>? ??
            const []);
    return items
        .whereType<Map<String, dynamic>>()
        .map(_podcastFromRemote)
        .toList();
  }

  Future<void> subscribe(String podcastId) =>
      _put('/api/v1/me/subscriptions/$podcastId', emptyBody: true);

  Future<void> unsubscribe(String podcastId) =>
      _delete('/api/v1/me/subscriptions/$podcastId');

  // ---- releases / health --------------------------------------------------

  Future<ReleaseInfo> checkUpdate({
    required String current,
    String platform = 'android',
    String channel = 'stable',
  }) async {
    final res = await _get('/api/v1/releases/latest', query: {
      'platform': platform,
      'channel': channel,
      'current': current,
    });
    return ReleaseInfo.fromJson(res.data as Map<String, dynamic>, baseUrl);
  }

  Future<bool> ping() async {
    try {
      await _get('/health');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- low-level helpers --------------------------------------------------

  /// Bearer-authenticated GET for callers that need the raw JSON envelope
  /// (e.g. the quota snapshot).
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) =>
      _guard(() => _dio.get(path, queryParameters: query));

  Future<Response<dynamic>> _get(String path,
          {Map<String, dynamic>? query}) =>
      get(path, query: query);

  Future<Response<dynamic>> _post(String path, {Object? data}) =>
      _guard(() => _dio.post(path, data: data));

  Future<Response<dynamic>> _put(String path, {bool emptyBody = false}) =>
      _guard(() =>
          _dio.put(path, data: emptyBody ? <String, dynamic>{} : null));

  Future<Response<dynamic>> _delete(String path) =>
      _guard(() => _dio.delete(path));

  Future<Response<dynamic>> _guard(
      Future<Response<dynamic>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  MlApiException _translate(DioException e) {
    final resp = e.response;
    final code = resp?.statusCode ?? 0;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return MlApiException('连接服务器超时，请检查网络或服务器地址', statusCode: 0);
      case DioExceptionType.connectionError:
        return MlApiException('无法连接服务器，请确认电脑端服务已开启', statusCode: 0);
      case DioExceptionType.cancel:
        return MlApiException('请求已取消', statusCode: 0);
      case DioExceptionType.badResponse:
        final detail = _detail(resp?.data);
        switch (code) {
          case 400:
            return MlApiException(detail ?? '请求参数有误', statusCode: code);
          case 401:
            return MlApiException(detail ?? '邮箱或密码不正确', statusCode: code);
          case 403:
            return MlApiException(detail ?? '账号已被禁用，请联系管理员',
                statusCode: code);
          case 404:
            return MlApiException(detail ?? '内容不存在或已下架', statusCode: code);
          case 409:
            return MlApiException(detail ?? '该邮箱已注册，请直接登录',
                statusCode: code);
          case 422:
            return MlApiException('提交的信息格式有误，请检查后重试',
                statusCode: code);
          case 503:
            return MlApiException('服务暂不可用，请稍后再试', statusCode: code);
          default:
            return MlApiException(detail ?? '服务器异常（$code），请稍后再试',
                statusCode: code);
        }
      case DioExceptionType.badCertificate:
        return MlApiException('服务器安全证书校验失败', statusCode: 0);
      case DioExceptionType.unknown:
        return MlApiException('网络异常，请稍后再试', statusCode: 0, raw: e.error);
      case DioExceptionType.transformTimeout:
        return MlApiException('请求转换超时，请稍后再试', statusCode: 0);
    }
  }

  static String? _detail(dynamic data) {
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      // FastAPI validation errors arrive as a list of {msg}.
      if (d is List && d.isNotEmpty) {
        final msg = d.first is Map ? (d.first as Map)['msg'] : d.first;
        if (msg != null) return msg.toString();
      }
      return d.toString();
    }
    return null;
  }

  /// Joins a possibly-relative [url] against [base]. Absolute http(s) URLs,
  /// asset URLs and empty values are returned untouched.
  static String absoluteUrl(String base, String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('asset://') ||
        url.startsWith('content://') ||
        url.startsWith('file://')) {
      return url;
    }
    var b = base.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    final u = url.startsWith('/') ? url : '/$url';
    return '$b$u';
  }
}

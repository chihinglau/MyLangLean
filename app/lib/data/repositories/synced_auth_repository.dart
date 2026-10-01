import 'dart:async';
import 'dart:math';

import '../../domain/entities/quota.dart';
import '../../domain/repositories/repositories.dart';
import '../kv_store.dart';
import '../remote/ml_api.dart';

/// Online auth repository.
///
/// Persistence layout stays compatible with [PersistentAuthRepository]
/// (`auth.isGuest/auth.name/auth.email/quota.*`) and adds the server JWT
/// (`auth.token`) plus a stable device id (`auth.deviceId`). Every server
/// failure degrades to the last known local state so the app stays usable
/// fully offline.
class SyncedAuthRepository implements AuthRepository {
  SyncedAuthRepository(this._kv, this._api) {
    _deviceId = _kv.getString(_kDeviceId) ?? _generateDeviceId();
    _api.token = _kv.getString(_kToken);
    _account = _loadAccount();
    _quota = _loadQuota();
  }

  static const _kToken = 'auth.token';
  static const _kGuest = 'auth.isGuest';
  static const _kName = 'auth.name';
  static const _kEmail = 'auth.email';
  static const _kDeviceId = 'auth.deviceId';
  static const _kUsedSec = 'quota.usedSec';
  static const _kLimitSec = 'quota.limitSec';
  static const _kNotice = 'auth.notice';

  final KvStore _kv;
  final MlApi _api;
  late String _deviceId;
  late Account _account;
  late UserQuota _quota;

  /// Broadcast whenever the resolved account changes (login, logout, guest
  /// downgrade, startup validation). UI uses this to refresh after the
  /// asynchronous startup session check.
  final StreamController<Account> _accountController =
      StreamController<Account>.broadcast();
  Stream<Account> get accountChanges => _accountController.stream;

  /// Fires with a human-readable message when a session is invalidated
  /// server-side (e.g. account disabled) after startup.
  final StreamController<String> _noticeController =
      StreamController<String>.broadcast();
  Stream<String> get notices => _noticeController.stream;

  /// Resolves once the first [ensureSession] call has finished, regardless
  /// of when listeners attach.
  Future<Account>? get sessionReady => _sessionReady;
  Future<Account>? _sessionReady;

  String get deviceId => _deviceId;

  static String _generateDeviceId() {
    final rnd = Random.secure();
    final id =
        '${DateTime.now().millisecondsSinceEpoch}-${rnd.nextInt(0xffffff)}';
    return id;
  }

  Account _loadAccount() {
    final isGuest = _kv.getBool(_kGuest) ?? true;
    if (isGuest) return Account(isGuest: true, deviceId: _deviceId);
    return Account(
      isGuest: false,
      name: _kv.getString(_kName),
      email: _kv.getString(_kEmail),
    );
  }

  UserQuota _loadQuota() => UserQuota(
        usedSec: (_kv.get(_kUsedSec) as num?)?.toInt() ?? 0,
        limitSec: (_kv.get(_kLimitSec) as num?)?.toInt() ?? 6000,
        isGuest: _kv.getBool(_kGuest) ?? true,
      );

  @override
  Account current() => _account;

  @override
  UserQuota quota() => _quota;

  /// Pops a one-shot account notice (e.g. "账号已被禁用"), set when a stored
  /// session was invalidated server-side during [ensureSession].
  Future<String?> consumeNotice() async {
    final notice = _kv.getString(_kNotice);
    if (notice != null) await _kv.remove(_kNotice);
    return notice;
  }

  /// Called once at startup: validates a stored JWT, otherwise obtains a
  /// guest session. Network failures keep whatever local state exists.
  /// The result future is exposed via [sessionReady].
  Future<Account> ensureSession() {
    return _sessionReady ??= _ensureSession();
  }

  Future<Account> _ensureSession() async {
    await _kv.set(_kDeviceId, _deviceId);
    final token = _kv.getString(_kToken);
    if (token != null && token.isNotEmpty) {
      _api.token = token;
      try {
        final acc = await _api.me();
        _applyRemoteAccount(acc);
        await _persist();
        await _refreshQuota();
        _accountController.add(_account);
        return _account;
      } on MlApiException catch (e) {
        // Expired/revoked token (401) or disabled account (403): drop the
        // session and continue as a guest rather than keeping a dead login.
        if (e.statusCode == 401 || e.statusCode == 403) {
          final message = e.statusCode == 403 && e.friendlyMessage.isNotEmpty
              ? e.friendlyMessage
              : null;
          // Persist + announce the notice independently; a storage failure
          // must never prevent the in-memory downgrade below.
          if (message != null) {
            unawaited(_kv.set(_kNotice, message).catchError((_) {}));
            _noticeController.add(message);
          }
          await _downgradeToGuest();
          return _account;
        }
      } catch (_) {
        // Offline: trust the cached session.
      }
      return _account;
    }
    return _guestLogin();
  }

  /// Forces the in-memory + persisted state back to a fresh guest session.
  /// Used when a stored session is discovered dead at startup.
  Future<void> _downgradeToGuest() async {
    _api.token = null;
    _account = Account(isGuest: true, deviceId: _deviceId);
    _quota = _quota.copyWith(isGuest: true);
    try {
      await _kv.remove(_kToken);
    } catch (_) {
      // The guest persist below rewrites all auth keys anyway.
    }
    await _guestLogin();
  }

  @override
  Future<Account> register({
    required String email,
    required String password,
    String? name,
  }) async {
    final session =
        await _api.register(email: email, password: password, name: name);
    _applySession(session);
    await _persist();
    await _refreshQuota();
    _accountController.add(_account);
    return _account;
  }

  @override
  Future<Account> login({
    required String email,
    required String password,
  }) async {
    final session = await _api.login(email: email, password: password);
    _applySession(session);
    await _persist();
    await _refreshQuota();
    _accountController.add(_account);
    return _account;
  }

  @override
  Future<Account> loginAsGuest() => _guestLogin();

  Future<Account> _guestLogin() async {
    try {
      final session = await _api.loginAsGuest(_deviceId);
      _applySession(session);
    } catch (_) {
      // Offline guest: still usable locally, just without sync.
      _account = Account(isGuest: true, deviceId: _deviceId);
      _quota = _quota.copyWith(isGuest: true);
      _api.token = null;
    }
    await _persist();
    _accountController.add(_account);
    return _account;
  }

  @override
  Future<void> logout() async {
    await _clearToken();
    _account = Account(isGuest: true, deviceId: _deviceId);
    _quota = _quota.copyWith(isGuest: true);
    await _persist();
    // Re-acquire an anonymous guest session so subscriptions can still sync.
    await _guestLogin();
    _accountController.add(_account);
  }

  void _applySession(AuthSession session) {
    _api.token = session.token;
    final acc = session.account;
    final email = acc?.email;
    final fallbackName = email?.split('@').first;
    _account = Account(
      isGuest: session.isGuest,
      email: email,
      name: (acc != null && acc.name.isNotEmpty) ? acc.name : fallbackName,
      deviceId: session.isGuest ? _deviceId : null,
    );
    _quota = _quota.copyWith(isGuest: session.isGuest);
  }

  void _applyRemoteAccount(RemoteAccount acc) {
    _account = Account(
      isGuest: acc.isGuest,
      email: acc.email,
      name: acc.name.isNotEmpty ? acc.name : acc.email?.split('@').first,
      deviceId: acc.isGuest ? _deviceId : null,
    );
    _quota = _quota.copyWith(isGuest: acc.isGuest);
  }

  /// Best effort quota refresh; never blocks login on failure.
  Future<void> _refreshQuota() async {
    try {
      final dio = _api;
      // Use the same bearer-authenticated client via a tiny direct call.
      final res = await dio.get('/api/v1/quota');
      final data = res.data as Map<String, dynamic>;
      _quota = UserQuota(
        usedSec: (data['used_sec'] as num?)?.toInt() ?? _quota.usedSec,
        limitSec: (data['limit_sec'] as num?)?.toInt() ?? _quota.limitSec,
        isGuest: _account.isGuest,
      );
      await _persist();
    } catch (_) {
      // Keep the cached snapshot.
    }
  }

  Future<void> _clearToken() async {
    _api.token = null;
    await _kv.remove(_kToken);
  }

  Future<void> _persist() async {
    await _kv.set(_kToken, _api.token);
    await _kv.set(_kDeviceId, _deviceId);
    await _kv.set(_kGuest, _account.isGuest);
    await _kv.set(_kName, _account.name);
    await _kv.set(_kEmail, _account.email);
    await _kv.set(_kUsedSec, _quota.usedSec);
    await _kv.set(_kLimitSec, _quota.limitSec);
  }
}

import '../../domain/entities/quota.dart';
import '../../domain/repositories/repositories.dart';
import '../kv_store.dart';

/// Production auth repository: the guest/login session and the local quota
/// snapshot persist in [KvStore] so the profile page keeps its state across
/// restarts. Server-issued JWT replaces this in the online phase; the
/// repository contract stays unchanged.
class PersistentAuthRepository implements AuthRepository {
  PersistentAuthRepository(this._kv, {this.deviceId = 'android-device'}) {
    _account = _loadAccount();
    _quota = _loadQuota();
  }

  static const _kGuest = 'auth.isGuest';
  static const _kName = 'auth.name';
  static const _kEmail = 'auth.email';
  static const _kUsedSec = 'quota.usedSec';
  static const _kLimitSec = 'quota.limitSec';

  final KvStore _kv;
  final String deviceId;

  late Account _account;
  late UserQuota _quota;

  Account _loadAccount() {
    final isGuest = _kv.getBool(_kGuest) ?? true;
    if (isGuest) return Account(isGuest: true, deviceId: deviceId);
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

  @override
  Future<Account> loginAsGuest() async {
    _account = Account(isGuest: true, deviceId: deviceId);
    _quota = _quota.copyWith(isGuest: true);
    await _persist();
    return _account;
  }

  @override
  Future<Account> login(
      {required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _account = Account(
      isGuest: false,
      name: email.split('@').first,
      email: email,
    );
    _quota = _quota.copyWith(isGuest: false);
    await _persist();
    return _account;
  }

  /// Offline build keeps register as a local-only alias (the online build
  /// swaps this repository for [SyncedAuthRepository]).
  @override
  Future<Account> register({
    required String email,
    required String password,
    String? name,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _account = Account(
      isGuest: false,
      name: (name != null && name.isNotEmpty)
          ? name
          : email.split('@').first,
      email: email,
    );
    _quota = _quota.copyWith(isGuest: false);
    await _persist();
    return _account;
  }

  @override
  Future<void> logout() async {
    _account = Account(isGuest: true, deviceId: deviceId);
    _quota = _quota.copyWith(isGuest: true);
    await _persist();
  }

  Future<void> _persist() async {
    await _kv.set(_kGuest, _account.isGuest);
    await _kv.set(_kName, _account.name);
    await _kv.set(_kEmail, _account.email);
    await _kv.set(_kUsedSec, _quota.usedSec);
    await _kv.set(_kLimitSec, _quota.limitSec);
  }
}

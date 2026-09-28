/// Monthly transcription quota (seconds).
class UserQuota {
  const UserQuota({
    required this.usedSec,
    this.limitSec = 6000, // 100 minutes per month, same as OORA
    this.isGuest = true,
  });

  final int usedSec;
  final int limitSec;
  final bool isGuest;

  int get remainingSec => (limitSec - usedSec).clamp(0, limitSec);
  double get usedRatio => limitSec == 0 ? 0 : usedSec / limitSec;

  UserQuota copyWith({int? usedSec, int? limitSec, bool? isGuest}) =>
      UserQuota(
        usedSec: usedSec ?? this.usedSec,
        limitSec: limitSec ?? this.limitSec,
        isGuest: isGuest ?? this.isGuest,
      );
}

class Account {
  const Account({
    required this.isGuest,
    this.name,
    this.email,
    this.deviceId,
  });

  final bool isGuest;
  final String? name;
  final String? email;
  final String? deviceId;

  String get displayName => name ?? (isGuest ? '游客' : '学习者');
}

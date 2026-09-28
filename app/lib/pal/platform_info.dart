import 'dart:io' show Platform;

/// Runtime platform detection that compiles on BOTH the official Flutter
/// (future iOS port) and Flutter-OH. Never reference OH-private enum values
/// in business code.
bool get isOhos {
  try {
    return Platform.operatingSystem == 'ohos';
  } catch (_) {
    return false;
  }
}

bool get isIOS {
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}

bool get isAndroid {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

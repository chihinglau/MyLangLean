import 'dart:async';

import 'package:flutter/services.dart';

/// Status of an OTA download/install session as reported by the native
/// updater plugin.
enum UpdateStatus {
  /// Download in progress; [received]/[total] carry the byte counters.
  progress,

  /// Download finished, the system package installer UI is being launched.
  installing,

  /// The device needs the "install unknown apps" permission (Android 8+);
  /// the OS settings page has been opened.
  needPermission,

  /// Download/install failed; [message] carries the reason.
  error,
}

class UpdateEvent {
  const UpdateEvent(
    this.status, {
    this.received = 0,
    this.total = 0,
    this.message,
  });

  final UpdateStatus status;
  final int received;
  final int total;
  final String? message;

  double? get fraction => total > 0 ? (received / total).clamp(0, 1) : null;
}

/// PAL for OTA updates.
///
/// Protocol (Android `MlUpdaterPlugin`):
///   * EventChannel `ml/updater/events` - download/install progress stream;
///     listen argument is a map `{url, sha256?, id?}` (a bare URL string is
///     still accepted by the native side for compatibility).
///   * MethodChannel `ml/updater` `cancel` - abort a running download.
///
/// Platforms without a registered plugin (HarmonyOS, desktop, iOS) get a
/// [MissingPluginException] and the UI falls back to manual instructions.
class UpdaterService {
  static const MethodChannel _method = MethodChannel('ml/updater');
  static const EventChannel _events = EventChannel('ml/updater/events');

  Stream<UpdateEvent> downloadAndInstall(
    String url, {
    String? sha256,
    int? releaseId,
  }) {
    final args = <String, dynamic>{
      'url': url,
      if (sha256 != null && sha256.isNotEmpty) 'sha256': sha256,
      if (releaseId != null && releaseId > 0) 'id': releaseId,
    };
    return _events
        .receiveBroadcastStream(args)
        .map((dynamic raw) => _parse(raw));
  }

  Future<void> cancel() async {
    try {
      await _method.invokeMethod('cancel');
    } on MissingPluginException {
      // Nothing running / unsupported - ignore.
    } on PlatformException {
      // Same.
    }
  }

  UpdateEvent _parse(dynamic raw) {
    if (raw is! Map) {
      return const UpdateEvent(UpdateStatus.error,
          message: '升级插件返回数据异常');
    }
    final map = Map<dynamic, dynamic>.from(raw);
    final status = (map['status'] ?? '').toString();
    final received = (map['received'] as num?)?.toInt() ?? 0;
    final total = (map['total'] as num?)?.toInt() ?? 0;
    final message = map['message'] as String?;
    switch (status) {
      case 'installing':
        return const UpdateEvent(UpdateStatus.installing);
      case 'needPermission':
        return const UpdateEvent(UpdateStatus.needPermission);
      case 'error':
        return UpdateEvent(UpdateStatus.error,
            message: message ?? '下载失败，请稍后重试');
      case 'progress':
      default:
        return UpdateEvent(UpdateStatus.progress,
            received: received, total: total);
    }
  }
}

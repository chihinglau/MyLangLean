import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../data/remote/ml_api.dart';
import '../../pal/updater_service.dart';

/// Checks the PC service for a newer release and drives the whole OTA UX:
/// prompt dialog -> in-app download with progress -> system installer
/// (or manual instructions on unsupported platforms).
///
/// Auto checks (startup) stay completely silent when there is nothing to
/// install or the server is unreachable.
Future<void> runUpdateCheck({
  required BuildContext context,
  required MlApi api,
  bool manual = false,
  UpdaterService? updater,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String text) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  final ReleaseInfo info;
  try {
    info = await api.checkUpdate(current: Env.appVersionWithBuild);
  } on MlApiException catch (e) {
    if (manual) toast(e.friendlyMessage);
    return;
  } catch (_) {
    if (manual) toast('检查更新失败，请稍后再试');
    return;
  }

  if (!info.hasUpdate) {
    if (manual) toast('当前已是最新版本（${Env.appVersion}）');
    return;
  }
  if (!context.mounted) return;
  await showUpdateFlow(context, info, updater: updater);
}

/// Shows the prompt -> download -> installer chain for an already-fetched
/// [info] (used by the throttled startup check).
Future<void> showUpdateFlow(
  BuildContext context,
  ReleaseInfo info, {
  UpdaterService? updater,
}) async {
  final confirmed = await _showUpdatePrompt(context, info);
  if (confirmed != true) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _DownloadDialog(
      release: info,
      updater: updater ?? UpdaterService(),
    ),
  );
}

/// Silent version check; returns null on any failure.
Future<ReleaseInfo?> fetchUpdateQuietly(MlApi api) async {
  try {
    final info = await api.checkUpdate(current: Env.appVersionWithBuild);
    return info.hasUpdate ? info : null;
  } catch (_) {
    return null;
  }
}

Future<bool?> _showUpdatePrompt(BuildContext context, ReleaseInfo info) {
  final sizeMb = info.size > 0 ? ' · ${formatMb(info.size)}' : '';
  return showDialog<bool>(
    context: context,
    barrierDismissible: !info.mandatory,
    useRootNavigator: true,
    builder: (ctx) => PopScope(
      canPop: !info.mandatory,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text('发现新版本 ${info.version}')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本号：${info.version}${info.buildNo > 0 ? ' (${info.buildNo})' : ''}$sizeMb',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 10),
            if (info.notes.trim().isNotEmpty)
              Text(info.notes.trim(),
                  style: const TextStyle(height: 1.5)),
            if (info.notes.trim().isEmpty)
              const Text('修复了已知问题并优化使用体验。'),
          ],
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('稍后再说'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    ),
  );
}

/// Formats byte counts as megabytes.
String formatMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  final kb = bytes / 1024;
  return '${kb.toStringAsFixed(0)} KB';
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.release, required this.updater});

  final ReleaseInfo release;
  final UpdaterService updater;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  StreamSubscription<UpdateEvent>? _sub;
  int _received = 0;
  int _total = 0;
  bool _installing = false;
  String? _error;
  bool _unsupported = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() {
      _received = 0;
      _total = widget.release.size;
      _installing = false;
      _error = null;
      _unsupported = false;
    });
    _sub?.cancel();
    _sub = widget.updater
        .downloadAndInstall(
          widget.release.url,
          sha256: widget.release.sha256,
          releaseId: widget.release.id,
        )
        .listen(
      (event) {
        if (!mounted) return;
        switch (event.status) {
          case UpdateStatus.progress:
            setState(() {
              _received = event.received;
              if (event.total > 0) _total = event.total;
            });
          case UpdateStatus.installing:
            setState(() => _installing = true);
          case UpdateStatus.needPermission:
            Navigator.of(context).pop();
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('请在系统设置中允许安装未知应用，然后重新点击更新'),
              ),
            );
          case UpdateStatus.error:
            setState(() => _error = event.message ?? '下载失败');
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        if (error is MissingPluginException ||
            error is UnimplementedError ||
            (error is PlatformException &&
                (error.code == 'missing-plugin' ||
                    error.code == 'UnimplementedError'))) {
          setState(() => _unsupported = true);
        } else if (error is PlatformException) {
          setState(() => _error = error.message ?? '下载失败');
        } else {
          setState(() => _error = '下载失败：$error');
        }
      },
      onDone: () {
        // Installer UI is up (or unsupported handled separately); the dialog
        // closes itself after a short beat so the user sees the final state.
        if (_installing && mounted) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) {
      return AlertDialog(
        title: const Text('当前平台暂不支持应用内安装'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请在电脑端管理台或通过以下地址手动下载安装包：'),
            const SizedBox(height: 10),
            SelectableText(widget.release.url,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: widget.release.url));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('复制链接'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    }

    final fraction =
        _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    final percent = fraction == null ? '' : '${(fraction * 100).toStringAsFixed(0)}%';

    return PopScope(
      canPop: !widget.release.mandatory,
      child: AlertDialog(
      title: Text(_installing ? '正在调起安装器' : '正在下载更新'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(height: 1.5)),
          ] else ...[
            Row(
              children: [
                if (_installing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Expanded(
                    child: LinearProgressIndicator(
                      value: fraction?.toDouble(),
                      minHeight: 8,
                    ),
                  ),
                if (!_installing) ...[
                  const SizedBox(width: 12),
                  Text(percent.isEmpty ? '准备中…' : percent),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _installing
                  ? '请在系统安装界面确认安装，安装完成后会自动替换当前版本。'
                  : '${formatMb(_received)}${_total > 0 ? ' / ${formatMb(_total)}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null) ...[
          // 强制更新失败后只能重试，不允许关闭回到旧版本。
          if (!widget.release.mandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          FilledButton(
            onPressed: _start,
            child: const Text('重试'),
          ),
        ] else if (!_installing) ...[
          if (!widget.release.mandatory)
            TextButton(
              onPressed: () async {
                await widget.updater.cancel();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('取消下载'),
            ),
          if (widget.release.mandatory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('强制更新：下载完成前请不要关闭应用',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ),
        ] else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('后台等待'),
          ),
      ],
      ),
    );
  }
}

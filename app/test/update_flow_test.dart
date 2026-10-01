import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/remote/ml_api.dart';
import 'package:mylanglean/features/update/update_flow.dart';

const _methodChannel = MethodChannel('ml/updater');
const _eventChannel = EventChannel('ml/updater/events');

class _UpdateApi extends MlApi {
  _UpdateApi() : super(baseUrl: 'http://127.0.0.1:8000');

  ReleaseInfo result = ReleaseInfo.empty;
  Object? failure;

  @override
  Future<ReleaseInfo> checkUpdate({
    required String current,
    String platform = 'android',
    String channel = 'stable',
  }) async {
    if (failure != null) throw failure!;
    return result;
  }
}

Widget pumpHost(MlApi api) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runUpdateCheck(context: context, api: api, manual: true),
            child: const Text('检查'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('manual check shows "up to date" when no release',
      (tester) async {
    final api = _UpdateApi();
    await tester.pumpWidget(pumpHost(api));

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已是最新'), findsOneWidget);
  });

  testWidgets('update prompt shows release notes and both actions',
      (tester) async {
    final api = _UpdateApi()
      ..result = const ReleaseInfo(
        hasUpdate: true,
        version: '0.5.0',
        buildNo: 9,
        notes: '新增发现页网络同步',
        size: 2048,
        url: 'http://127.0.0.1:8000/api/v1/releases/download/9',
      );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runUpdateCheck(context: context, api: api, manual: true),
            child: const Text('检查'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 0.5.0'), findsOneWidget);
    expect(find.text('新增发现页网络同步'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);

    // Dismiss via "later".
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 0.5.0'), findsNothing);
  });

  testWidgets('mandatory update hides the dismiss action', (tester) async {
    final api = _UpdateApi()
      ..result = const ReleaseInfo(
        hasUpdate: true,
        version: '0.5.1',
        mandatory: true,
        notes: '必须更新',
        url: 'http://127.0.0.1:8000/api/v1/releases/download/10',
      );

    // Unsupported platform: native plugin reports a missing-plugin error.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _methodChannel, (call) async => null);
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      _eventChannel,
      MockStreamHandler.inline(
        onListen: (args, events) =>
            events.error(code: 'missing-plugin'),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runUpdateCheck(context: context, api: api, manual: true),
            child: const Text('检查'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();
    expect(find.text('稍后再说'), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);

    // Confirming starts the download; the unsupported-plugin error shows the
    // manual instructions dialog instead of crashing.
    await tester.tap(find.text('立即更新'));
    await tester.pump();
    await tester.pump();
    expect(find.text('当前平台暂不支持应用内安装'), findsOneWidget);
    expect(find.textContaining('/releases/download/10'), findsOneWidget);
  });

  testWidgets('download dialog shows progress then installer state',
      (tester) async {
    final api = _UpdateApi()
      ..result = const ReleaseInfo(
        hasUpdate: true,
        version: '0.5.0',
        size: 100,
        url: 'http://127.0.0.1:8000/api/v1/releases/download/9',
      );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _methodChannel, (call) async => null);
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      _eventChannel,
      MockStreamHandler.inline(
        onListen: (args, events) {
          events.success({
            'status': 'progress',
            'received': 40,
            'total': 100,
          });
          // Defer to a later frame so the UI shows progress first.
          Future<void>.delayed(const Duration(milliseconds: 100),
              () => events.success({'status': 'installing'}));
        },
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runUpdateCheck(context: context, api: api, manual: true),
            child: const Text('检查'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    // Platform-channel events are dispatched across several frames.
    await tester.pump();
    await tester.pump();
    expect(find.text('正在下载更新'), findsOneWidget);
    expect(find.textContaining('40%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在调起安装器'), findsOneWidget);

    // Close so the test does not outlive the infinite progress spinner.
    await tester.tap(find.text('后台等待'));
    await tester.pumpAndSettle();
  });

  testWidgets('mandatory download cannot be cancelled, even after failure',
      (tester) async {
    final api = _UpdateApi()
      ..result = const ReleaseInfo(
        hasUpdate: true,
        version: '0.5.1',
        mandatory: true,
        size: 100,
        url: 'http://127.0.0.1:8000/api/v1/releases/download/10',
      );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _methodChannel, (call) async => null);
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      _eventChannel,
      MockStreamHandler.inline(
        onListen: (args, events) {
          events.success({
            'status': 'progress',
            'received': 30,
            'total': 100,
          });
          Future<void>.delayed(const Duration(milliseconds: 50),
              () => events.error(code: 'DOWNLOAD_FAILED', message: '网络中断'));
        },
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runUpdateCheck(context: context, api: api, manual: true),
            child: const Text('检查'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pump();
    await tester.pump();

    // Downloading: no cancel button, only the mandatory-update hint.
    expect(find.text('取消下载'), findsNothing);
    expect(find.textContaining('强制更新'), findsOneWidget);

    // Failure state: retry is the sole action.
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('网络中断'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('manual check failure surfaces the friendly error',
      (tester) async {
    final api = _UpdateApi()
      ..failure = MlApiException('无法连接服务器，请确认电脑端服务已开启');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                runUpdateCheck(context: context, api: api, manual: true),
            child: const Text('检查'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法连接服务器'), findsOneWidget);
  });
}

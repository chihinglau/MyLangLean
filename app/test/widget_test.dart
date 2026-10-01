// Smoke test for the MyLangLean app shell.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mylanglean/app.dart';
import 'package:mylanglean/pal/pal_providers.dart';
import 'package:mylanglean/pal/mock/mock_audio_player.dart';
import 'package:mylanglean/pal/mock/mock_audio_recorder.dart';
import 'package:mylanglean/pal/mock/mock_media_picker.dart';

Widget boot() => ProviderScope(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(MockAudioPlayer()),
        audioRecorderServiceProvider.overrideWithValue(MockAudioRecorder()),
        mediaPickerServiceProvider.overrideWithValue(MockMediaPicker()),
      ],
      child: const MyLangLeanApp(),
    );

void main() {
  testWidgets('app boots into the discover shell with bottom navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(boot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('资料库'), findsOneWidget);
  });

  testWidgets('discover shows filter rows and the expanded catalog',
      (WidgetTester tester) async {
    await tester.pumpWidget(boot());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('全部语言'), findsOneWidget);
    expect(find.text('Real English Voices'), findsOneWidget);

    // Cards below the fold are lazily built; scroll to verify the new
    // Spanish / Chinese catalog entries exist.
    await tester.scrollUntilVisible(
      find.text('Hablemos Español'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('中文慢谈'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Hablemos Español'), findsOneWidget);
    expect(find.text('中文慢谈'), findsOneWidget);
  });

  testWidgets('history shows the empty state before any practice',
      (WidgetTester tester) async {
    await tester.pumpWidget(boot());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('履历'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有跟读记录'), findsOneWidget);
    expect(find.text('去选一集开始练'), findsOneWidget);
  });

  testWidgets('profile shows preferences and service entries',
      (WidgetTester tester) async {
    await tester.pumpWidget(boot());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('学习概览'), findsOneWidget);
    // The service/update card sits above the preferences card; scroll to
    // bring the preference chips into view.
    await tester.scrollUntilVisible(
      find.text('双语对照'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('双语对照'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);

    // Service/about entries sit below the tall preferences card.
    await tester.scrollUntilVisible(
      find.text('转录服务'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('转录服务'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关于 MyLangLean'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('关于 MyLangLean'), findsOneWidget);
  });
}

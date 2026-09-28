// Smoke test for the MyLangLean app shell.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mylanglean/app.dart';
import 'package:mylanglean/pal/pal_providers.dart';
import 'package:mylanglean/pal/mock/mock_audio_player.dart';
import 'package:mylanglean/pal/mock/mock_audio_recorder.dart';
import 'package:mylanglean/pal/mock/mock_media_picker.dart';

void main() {
  testWidgets('app boots into the discover shell with bottom navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(MockAudioPlayer()),
          audioRecorderServiceProvider.overrideWithValue(MockAudioRecorder()),
          mediaPickerServiceProvider.overrideWithValue(MockMediaPicker()),
        ],
        child: const MyLangLeanApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('资料库'), findsOneWidget);
  });
}

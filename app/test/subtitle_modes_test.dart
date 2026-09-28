// Coverage for the player's three subtitle states:
// source-only / bilingual (with or without translations) / blind listening.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mylanglean/domain/entities/transcript.dart';
import 'package:mylanglean/features/player/player_controller.dart';
import 'package:mylanglean/features/player/widgets/karaoke_subtitle.dart';

Transcript _transcript({bool translateFirst = false, bool translateNone = true}) {
  return Transcript(
    version: 1,
    language: 'en',
    duration: 4.0,
    segments: [
      TranscriptSegment(
        id: 0,
        start: 0,
        end: 2,
        text: 'Hello world.',
        translation:
            (translateFirst && !translateNone) ? '你好，世界。' : null,
        words: const [
          WordToken(w: 'Hello', s: 0.0, e: 1.0, p: 0.9),
          WordToken(w: 'world.', s: 1.0, e: 2.0, p: 0.9),
        ],
      ),
      TranscriptSegment(
        id: 1,
        start: 2,
        end: 4,
        text: 'Good morning.',
        // Intentionally untranslated in the partial case.
        translation: null,
        words: const [
          WordToken(w: 'Good', s: 2.0, e: 3.0, p: 0.9),
          WordToken(w: 'morning.', s: 3.0, e: 4.0, p: 0.9),
        ],
      ),
    ],
  );
}

Widget _host(KaraokeSubtitle sub) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 600, child: sub)),
    );

void main() {
  group('Transcript translation helpers', () {
    test('hasTranslations reflects per-segment glosses', () {
      expect(_transcript().hasTranslations, isFalse);
      final partial = _transcript(translateFirst: true, translateNone: false);
      expect(partial.hasTranslations, isTrue);
      expect(partial.translatedCount, 1);
    });
  });

  testWidgets('bilingual mode with zero translations shows guidance banner',
      (tester) async {
    final pos = ValueNotifier<Duration>(const Duration(milliseconds: 500));
    addTearDown(pos.dispose);
    await tester.pumpWidget(_host(KaraokeSubtitle(
      transcript: _transcript(),
      position: pos,
      mode: SubtitleMode.bilingual,
      fontScale: 1,
      loopEnabled: false,
      onSeekWord: (_) {},
      onToggleLoop: (_) {},
    )));

    expect(find.textContaining('当前字幕没有译文'), findsOneWidget);
    // Source words stay visible; no noisy per-line placeholder in this case.
    expect(find.textContaining('Hello', skipOffstage: false), findsWidgets);
    expect(find.textContaining('暂无译文'), findsNothing);

    // Banner is dismissible for the rest of the session.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.textContaining('当前字幕没有译文'), findsNothing);
  });

  testWidgets('bilingual mode marks sentences missing a gloss in place',
      (tester) async {
    final pos = ValueNotifier<Duration>(const Duration(milliseconds: 500));
    addTearDown(pos.dispose);
    final partial =
        _transcript(translateFirst: true, translateNone: false);
    await tester.pumpWidget(_host(KaraokeSubtitle(
      transcript: partial,
      position: pos,
      mode: SubtitleMode.bilingual,
      fontScale: 1,
      loopEnabled: false,
      onSeekWord: (_) {},
      onToggleLoop: (_) {},
    )));

    expect(find.text('你好，世界。'), findsOneWidget);
    expect(find.textContaining('暂无译文'), findsOneWidget);
    expect(find.textContaining('当前字幕没有译文'), findsNothing);
  });

  testWidgets('source-only mode shows neither glosses nor guidance',
      (tester) async {
    final pos = ValueNotifier<Duration>(const Duration(milliseconds: 500));
    addTearDown(pos.dispose);
    await tester.pumpWidget(_host(KaraokeSubtitle(
      transcript: _transcript(translateFirst: true, translateNone: false),
      position: pos,
      mode: SubtitleMode.sourceOnly,
      fontScale: 1,
      loopEnabled: false,
      onSeekWord: (_) {},
      onToggleLoop: (_) {},
    )));
    expect(find.text('你好，世界。'), findsNothing);
    expect(find.textContaining('当前字幕没有译文'), findsNothing);
    expect(find.textContaining('暂无译文'), findsNothing);
  });

  testWidgets('blind mode hides text until revealed, with gloss peek',
      (tester) async {
    final pos = ValueNotifier<Duration>(const Duration(milliseconds: 500));
    addTearDown(pos.dispose);
    final partial =
        _transcript(translateFirst: true, translateNone: false);
    await tester.pumpWidget(_host(KaraokeSubtitle(
      transcript: partial,
      position: pos,
      mode: SubtitleMode.hidden,
      fontScale: 1,
      loopEnabled: false,
      onSeekWord: (_) {},
      onToggleLoop: (_) {},
    )));

    expect(find.textContaining('盲听模式'), findsOneWidget);
    expect(find.text('Hello world.'), findsNothing);

    // Reveal the sentence currently playing.
    await tester.tap(find.text('显示当前句'));
    await tester.pump();
    expect(find.text('Hello world.'), findsOneWidget);
    expect(find.text('你好，世界。'), findsNothing);

    // Peek at the gloss, then hide it again.
    await tester.tap(find.text('看译文'));
    await tester.pump();
    expect(find.text('你好，世界。'), findsOneWidget);
    await tester.tap(find.text('隐藏译文'));
    await tester.pump();
    expect(find.text('你好，世界。'), findsNothing);

    // Back to pure listening: the sentence disappears.
    await tester.tap(find.text('继续盲听'));
    await tester.pump();
    expect(find.text('Hello world.'), findsNothing);
    expect(find.text('显示当前句'), findsOneWidget);
  });
}

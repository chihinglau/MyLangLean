import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/practice_store.dart';
import 'package:mylanglean/domain/entities/recording.dart';

Recording _rec(String id,
        {int overall = 80, int durationMs = 5000, DateTime? at}) =>
    Recording(
      id: id,
      episodeTitle: 'EP',
      sentence: 'hello $id',
      startMs: 0,
      endMs: 4000,
      durationMs: durationMs,
      filePath: '/tmp/$id.m4a',
      score: PronunciationScore(overall: overall),
      createdAt: at ?? DateTime(2026, 10, 1, 9),
    );

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mll-practice-test-');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('recordings survive reopen including durationMs', () async {
    final store = await PracticeStore.open(dir);
    await store.upsert(_rec('a', durationMs: 7250, overall: 91));
    await store.upsert(_rec('b', at: DateTime(2026, 10, 1, 10)));

    final reopened = await PracticeStore.open(dir);
    expect(reopened.entries, hasLength(2));
    final a = reopened.entries.firstWhere((r) => r.id == 'a');
    expect(a.durationMs, 7250);
    expect(a.practiceMs, 7250);
    expect(a.score.overall, 91);
    expect(a.sentence, 'hello a');
  });

  test('upsert replaces by id', () async {
    final store = await PracticeStore.open(dir);
    await store.upsert(_rec('a', overall: 60));
    await store.upsert(_rec('a', overall: 99));
    expect(store.entries, hasLength(1));
    expect(store.entries.single.score.overall, 99);
  });

  test('legacy rows without durationMs fall back to sentence span',
      () async {
    final file = File('${dir.path}${Platform.pathSeparator}'
        'recordings_index.json');
    file.writeAsStringSync('''
[
  {
    "id": "old",
    "episodeTitle": "EP",
    "sentence": "legacy",
    "startMs": 1000,
    "endMs": 5000,
    "filePath": "/tmp/old.m4a",
    "score": {"overall": 75},
    "createdAt": "2026-09-30T09:00:00"
  }
]
''');
    final store = await PracticeStore.open(dir);
    expect(store.entries.single.practiceMs, 4000);
  });

  test('remove returns the row and clear empties the index', () async {
    final store = await PracticeStore.open(dir);
    await store.upsert(_rec('a'));
    await store.upsert(_rec('b'));

    final removed = await store.remove('a');
    expect(removed?.id, 'a');
    expect(store.entries.map((r) => r.id), ['b']);

    await store.clear();
    expect(store.entries, isEmpty);
    final reopened = await PracticeStore.open(dir);
    expect(reopened.entries, isEmpty);
  });

  test('corrupt index is quarantined', () async {
    final file = File('${dir.path}${Platform.pathSeparator}'
        'recordings_index.json');
    file.writeAsStringSync('not json');

    final store = await PracticeStore.open(dir);
    expect(store.entries, isEmpty);
    await store.upsert(_rec('a'));
    final reopened = await PracticeStore.open(dir);
    expect(reopened.entries.single.id, 'a');
  });
}

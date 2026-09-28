import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/local_library_store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mll_lib_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('entries survive a fresh store open', () async {
    final first = await LocalLibraryStore.open(tmp);
    await first.add(
      title: 'lesson.mp3',
      mediaPath: '${tmp.path}/lesson.mp3',
      transcriptPath: '${tmp.path}/lesson.json',
      durationMs: 3620,
      language: 'en',
    );

    final second = await LocalLibraryStore.open(tmp);
    expect(second.entries, hasLength(1));
    final e = second.entries.single;
    expect(e.title, 'lesson.mp3');
    expect(e.transcriptPath, '${tmp.path}/lesson.json');
    expect(e.toEpisode().isLocal, isTrue);
    expect(e.toEpisode().duration.inMilliseconds, 3620);

    await second.updateTranscript(e.id, '${tmp.path}/v2.json');
    final third = await LocalLibraryStore.open(tmp);
    expect(third.entries.single.transcriptPath, '${tmp.path}/v2.json');

    await third.remove(e.id);
    final fourth = await LocalLibraryStore.open(tmp);
    expect(fourth.entries, isEmpty);
  });

  test('corrupt index is quarantined and starts empty', () async {
    final indexFile = File('${tmp.path}/library_index.json');
    indexFile.writeAsStringSync('{broken');

    final store = await LocalLibraryStore.open(tmp);
    expect(store.entries, isEmpty);
    expect(
      tmp.listSync().any((f) => f.path.contains('library_index.json.corrupt-')),
      isTrue,
    );

    // Library stays usable after corruption.
    await store.add(title: 'ok', mediaPath: '${tmp.path}/ok.mp3');
    final reopened = await LocalLibraryStore.open(tmp);
    expect(reopened.entries.single.title, 'ok');
  });
}

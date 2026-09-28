import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/repositories/mock_repositories.dart';
import 'package:mylanglean/domain/entities/episode.dart';
import 'package:mylanglean/domain/entities/transcript.dart';

/// A JSON produced by the Windows Subtitle Studio must load unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixtureFile =
      File('test/fixtures/tool_sample_transcript.json').absolute;

  test('studio-exported fixture parses into the transcript model', () {
    final json = jsonDecode(fixtureFile.readAsStringSync())
        as Map<String, dynamic>;
    final t = Transcript.fromJson(json);

    expect(t.version, 1);
    expect(t.language, 'en');
    expect(t.duration, closeTo(3.62, 1e-9));
    expect(t.segments, hasLength(2));
    expect(t.segments.first.words, hasLength(3));
    expect(t.segments.last.translation, isNull);
    expect(t.index.wordAt(0.7)?.token.w, 'export');
    expect(t.index.wordAt(3.3)?.token.w, 'voice.');
    expect(t.index.segmentAt(2.5, t.segments), 1);
  });

  test('malformed transcript JSON throws FormatException', () {
    expect(
      () => Transcript.fromJson(jsonDecode('{oops') as Map<String, dynamic>),
      throwsFormatException,
    );
  });

  group('LocalAwareTranscriptRepository', () {
    late Directory tmp;
    late LocalAwareTranscriptRepository repo;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mll_tr_test');
      repo = LocalAwareTranscriptRepository();
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('reads a sidecar transcript from disk', () async {
      final sidecar = File('${tmp.path}/lesson.mll.json')
        ..writeAsStringSync(fixtureFile.readAsStringSync());
      final ep = Episode(
        id: 'local-1',
        title: 'lesson',
        audioUrl: '${tmp.path}/lesson.mp3',
        isLocal: true,
        localPath: '${tmp.path}/lesson.mp3',
        transcriptPath: sidecar.path,
      );

      final t = await repo.transcriptFor(ep);
      expect(t, isNotNull);
      expect(t!.segments.first.words.first.w, 'Studio');
    });

    test('missing sidecar throws TranscriptException', () async {
      final ep = Episode(
        id: 'local-2',
        title: 'gone',
        audioUrl: '${tmp.path}/gone.mp3',
        isLocal: true,
        localPath: '${tmp.path}/gone.mp3',
        transcriptPath: '${tmp.path}/does-not-exist.json',
      );
      expect(() => repo.transcriptFor(ep), throwsA(isA<TranscriptException>()));
    });

    test('corrupt sidecar throws FormatException-derived failure', () async {
      final sidecar = File('${tmp.path}/bad.json')
        ..writeAsStringSync('{not json');
      final ep = Episode(
        id: 'local-3',
        title: 'bad',
        audioUrl: '${tmp.path}/bad.mp3',
        isLocal: true,
        localPath: '${tmp.path}/bad.mp3',
        transcriptPath: sidecar.path,
      );
      expect(() => repo.transcriptFor(ep), throwsA(isA<TranscriptException>()));
    });

    test('imported media without sidecar resolves to no transcript',
        () async {
      final ep = Episode(
        id: 'local-4',
        title: 'plain',
        audioUrl: '${tmp.path}/plain.mp3',
        isLocal: true,
        localPath: '${tmp.path}/plain.mp3',
      );
      expect(await repo.transcriptFor(ep), isNull);
    });
  });
}

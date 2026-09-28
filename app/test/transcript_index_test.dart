import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/domain/entities/transcript.dart';

void main() {
  final transcript = Transcript(
    version: 1,
    language: 'en',
    duration: 5,
    segments: [
      TranscriptSegment(
        id: 0,
        start: 0,
        end: 2,
        text: 'hello world',
        words: const [
          WordToken(w: 'hello', s: 0, e: 1),
          WordToken(w: 'world', s: 1, e: 2),
        ],
      ),
      TranscriptSegment(
        id: 1,
        start: 2.5,
        end: 5,
        text: 'goodbye',
        words: const [
          WordToken(w: 'goodbye', s: 2.5, e: 5),
        ],
      ),
    ],
  );

  test('binary-search finds the active word', () {
    expect(transcript.index.wordAt(0.5)?.token.w, 'hello');
    expect(transcript.index.wordAt(1.5)?.token.w, 'world');
    expect(transcript.index.wordAt(3.0)?.token.w, 'goodbye');
  });

  test('gaps and silence return null word', () {
    expect(transcript.index.wordAt(2.2), isNull);
    expect(transcript.index.wordAt(100), isNull);
  });

  test('active segment falls back to previous segment in gaps', () {
    expect(transcript.index.segmentAt(2.2, transcript.segments), 0);
    expect(transcript.index.segmentAt(4.9, transcript.segments), 1);
  });

  test('parse sample JSON from assets schema', () {
    const json = {
      'version': 1,
      'language': 'en',
      'duration': 2.1,
      'segments': [
        {
          'id': 0,
          'start': 0.0,
          'end': 2.1,
          'text': 'hi',
          'translation': '你好',
          'words': [
            {'w': 'hi', 's': 0.0, 'e': 2.1, 'p': 0.9}
          ],
        }
      ],
    };
    final t = Transcript.fromJson(json);
    expect(t.segments.single.translation, '你好');
    expect(t.segments.single.words.single.p, 0.9);
  });
}

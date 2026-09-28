/// Word-level token with timestamps (produced by ASR, e.g. faster-whisper).
class WordToken {
  const WordToken({
    required this.w,
    required this.s,
    required this.e,
    this.p,
  });

  final String w;

  /// start / end in seconds
  final double s;
  final double e;

  /// ASR confidence 0..1
  final double? p;

  bool covers(double t) => t >= s && t < e;

  factory WordToken.fromJson(Map<String, dynamic> json) => WordToken(
        w: json['w'] as String,
        s: (json['s'] as num).toDouble(),
        e: (json['e'] as num).toDouble(),
        p: (json['p'] as num?)?.toDouble(),
      );
}

class TranscriptSegment {
  TranscriptSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    this.translation,
    List<WordToken>? words,
  }) : words = words ?? const [];

  final int id;
  final double start;
  final double end;
  final String text;
  final String? translation;
  final List<WordToken> words;

  Duration get startOffset => Duration(milliseconds: (start * 1000).round());
  Duration get endOffset => Duration(milliseconds: (end * 1000).round());

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) =>
      TranscriptSegment(
        id: (json['id'] as num).toInt(),
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        text: json['text'] as String? ?? '',
        translation: json['translation'] as String?,
        words: (json['words'] as List<dynamic>?)
                ?.map((e) => WordToken.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// Word-by-word transcript. Shared format across HarmonyOS / iOS / server.
/// Schema is frozen; bump [version] only for breaking changes.
class Transcript {
  Transcript({
    required this.version,
    required this.language,
    required this.duration,
    required this.segments,
  }) {
    _index = TranscriptIndex(this);
  }

  final int version;
  final String language;
  final double duration;
  final List<TranscriptSegment> segments;
  late final TranscriptIndex _index;

  TranscriptIndex get index => _index;

  Duration get totalDuration =>
      Duration(milliseconds: (duration * 1000).round());

  factory Transcript.fromJson(Map<String, dynamic> json) => Transcript(
        version: (json['version'] as num?)?.toInt() ?? 1,
        language: json['language'] as String? ?? 'en',
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        segments: (json['segments'] as List<dynamic>)
            .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FlatWord {
  const FlatWord(this.segmentId, this.wordIndex, this.token);
  final int segmentId;
  final int wordIndex;
  final WordToken token;
}

/// Binary-search index over the flattened word list.
class TranscriptIndex {
  TranscriptIndex(Transcript t) {
    for (final seg in t.segments) {
      for (var i = 0; i < seg.words.length; i++) {
        _words.add(FlatWord(seg.id, i, seg.words[i]));
      }
    }
  }

  final List<FlatWord> _words = [];

  /// Returns the active word at time [t] (seconds), or null in gaps/silence.
  FlatWord? wordAt(double t) {
    if (_words.isEmpty) return null;
    var lo = 0;
    var hi = _words.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final w = _words[mid].token;
      if (t < w.s) {
        hi = mid - 1;
      } else if (t >= w.e) {
        lo = mid + 1;
      } else {
        return _words[mid];
      }
    }
    return null;
  }

  /// Segment active at [t]. Falls back to nearest previous segment.
  int segmentAt(double t, List<TranscriptSegment> segments) {
    var lo = 0;
    var hi = segments.length - 1;
    var result = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (t >= segments[mid].start) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  /// Next word boundary after [t], used for mock-player sentence loops.
  double? endOfSegment(double t, List<TranscriptSegment> segments) {
    final i = segmentAt(t, segments);
    return segments[i].end;
  }
}

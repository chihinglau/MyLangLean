/// Result of one shadowing attempt.
class PronunciationScore {
  const PronunciationScore({
    required this.overall,
    this.rhythm = 0,
    this.fluency = 0,
    this.intonation = 0,
    this.suggestions = const [],
  });

  /// 0..100
  final int overall;
  final int rhythm;
  final int fluency;
  final int intonation;
  final List<String> suggestions;

  factory PronunciationScore.fromJson(Map<String, dynamic> json) =>
      PronunciationScore(
        overall: (json['overall'] as num?)?.toInt() ?? 0,
        rhythm: (json['rhythm'] as num?)?.toInt() ?? 0,
        fluency: (json['fluency'] as num?)?.toInt() ?? 0,
        intonation: (json['intonation'] as num?)?.toInt() ?? 0,
        suggestions: (json['suggestions'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'overall': overall,
        'rhythm': rhythm,
        'fluency': fluency,
        'intonation': intonation,
        'suggestions': suggestions,
      };
}

class Recording {
  const Recording({
    required this.id,
    required this.episodeTitle,
    required this.sentence,
    required this.startMs,
    required this.endMs,
    required this.filePath,
    required this.score,
    required this.createdAt,
  });

  final String id;
  final String episodeTitle;
  final String sentence;
  final int startMs;
  final int endMs;
  final String filePath;
  final PronunciationScore score;
  final DateTime createdAt;

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
        id: json['id'] as String,
        episodeTitle: json['episodeTitle'] as String? ?? '',
        sentence: json['sentence'] as String? ?? '',
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        filePath: json['filePath'] as String? ?? '',
        score: PronunciationScore.fromJson(
            json['score'] as Map<String, dynamic>? ?? const {}),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'episodeTitle': episodeTitle,
        'sentence': sentence,
        'startMs': startMs,
        'endMs': endMs,
        'filePath': filePath,
        'score': score.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };
}

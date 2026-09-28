import '../../domain/entities/recording.dart';

/// V1 heuristic pronunciation scoring.
///
/// Runs entirely on-device without an audio DSP dependency: compares the
/// learner's attempt duration / pause ratio / rate against the reference
/// segment. V2 will replace this with server-side forced alignment (GOP).
class ShadowScorer {
  const ShadowScorer();

  PronunciationScore score({
    required Duration reference,
    required Duration attempt,
    int pauseCount = 0,
  }) {
    final refMs = reference.inMilliseconds.clamp(500, 1 << 30);
    final attMs = attempt.inMilliseconds.clamp(500, 1 << 30);

    // Rhythm: closeness of attempt length to the original sentence.
    final lengthRatio = attMs / refMs;
    final rhythm =
        (100 - ((lengthRatio - 1.0).abs() * 120).clamp(0, 100)).round();

    // Fluency: penalise excessive mid-sentence pauses.
    final fluency = (100 - pauseCount * 12).clamp(40, 100);

    // Intonation placeholder (needs pitch contour in V2).
    const intonation = 78;

    final overall =
        (rhythm * 0.4 + fluency * 0.4 + intonation * 0.2).round();

    final suggestions = <String>[
      if (lengthRatio > 1.25) '整体偏慢，试着跟上主播的节奏连读。',
      if (lengthRatio < 0.8) '语速过快，注意每个词的完整发音。',
      if (pauseCount >= 2) '中间停顿较多，先把这一句拆成两半练习。',
      if (rhythm >= 85 && pauseCount <= 1) '节奏很好！尝试不看字幕再跟读一遍。',
    ];

    return PronunciationScore(
      overall: overall.clamp(0, 100),
      rhythm: rhythm.clamp(0, 100),
      fluency: fluency.clamp(0, 100),
      intonation: intonation,
      suggestions: suggestions.isEmpty ? const ['继续保持，多练几遍形成肌肉记忆。'] : suggestions,
    );
  }
}

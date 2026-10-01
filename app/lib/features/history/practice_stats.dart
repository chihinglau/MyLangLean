import '../../domain/entities/recording.dart';

/// One calendar day of practice, newest recordings first.
class DailyGroup {
  const DailyGroup({required this.day, required this.label, required this.records});

  final DateTime day;
  final String label;
  final List<Recording> records;
}

/// Derived, presentation-ready practice statistics. Pure logic so it can be
/// unit-tested without any Flutter binding.
class PracticeStats {
  const PracticeStats({
    required this.count,
    required this.totalSec,
    required this.avgScore,
    required this.bestScore,
    required this.streakDays,
    required this.scoreTrend,
    required this.groups,
  });

  final int count;
  final int totalSec;

  /// Mean overall score rounded to the nearest integer (0 when empty).
  final int avgScore;
  final int bestScore;

  /// Consecutive practice days ending today, or yesterday when the learner
  /// has not practised yet today (the streak is not broken until midnight).
  final int streakDays;

  /// Overall scores of the most recent attempts, oldest → newest, at most 10.
  final List<int> scoreTrend;

  /// Day groups, newest day first; recordings inside a day newest first.
  final List<DailyGroup> groups;

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  static String dayLabel(DateTime day, DateTime now) {
    final today = dayOf(now);
    final diff = today.difference(dayOf(day)).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${day.month}月${day.day}日';
  }

  factory PracticeStats.from(List<Recording> recordings, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final items = List<Recording>.of(recordings)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (items.isEmpty) {
      return const PracticeStats(
        count: 0,
        totalSec: 0,
        avgScore: 0,
        bestScore: 0,
        streakDays: 0,
        scoreTrend: [],
        groups: [],
      );
    }

    final totalSec = items.fold<int>(0, (s, r) => s + r.practiceMs) ~/ 1000;
    final avgScore =
        (items.fold<int>(0, (s, r) => s + r.score.overall) / items.length)
            .round();
    final bestScore = items
        .map((r) => r.score.overall)
        .reduce((a, b) => a > b ? a : b);

    // Day groups (items are newest first, preserving order inside a day).
    final groups = <DailyGroup>[];
    for (final r in items) {
      final day = dayOf(r.createdAt);
      if (groups.isEmpty || groups.last.day != day) {
        groups.add(DailyGroup(
            day: day, label: dayLabel(day, ref), records: <Recording>[]));
      }
      groups.last.records.add(r);
    }

    final streak = _streakDays(groups.map((g) => g.day).toSet(), ref);

    // Trend: oldest → newest, at most the last 10 attempts.
    final trend = items
        .map((r) => r.score.overall)
        .toList()
        .reversed
        .take(10)
        .toList();

    return PracticeStats(
      count: items.length,
      totalSec: totalSec,
      avgScore: avgScore,
      bestScore: bestScore,
      streakDays: streak,
      scoreTrend: trend,
      groups: groups,
    );
  }

  static int _streakDays(Set<DateTime> days, DateTime now) {
    if (days.isEmpty) return 0;
    var cursor = dayOf(now);
    // Not having practised yet today does not break the streak.
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/domain/entities/recording.dart';
import 'package:mylanglean/features/history/practice_stats.dart';

PronunciationScore _score(int overall) => PronunciationScore(
      overall: overall,
      rhythm: overall,
      fluency: overall,
      intonation: 78,
    );

Recording _rec({
  required DateTime at,
  int overall = 80,
  int durationMs = 5000,
  int startMs = 0,
  int endMs = 4000,
}) =>
    Recording(
      id: 'r-$at-$overall',
      episodeTitle: 'EP',
      sentence: 'hello world',
      startMs: startMs,
      endMs: endMs,
      durationMs: durationMs,
      filePath: '/tmp/x.m4a',
      score: _score(overall),
      createdAt: at,
    );

void main() {
  // Fixed "now" so the test never depends on the wall clock.
  final now = DateTime(2026, 10, 1, 10, 0);
  DateTime daysAgo(int n, {int hour = 9}) =>
      DateTime(2026, 9, 30 - (n - 1), hour);

  group('PracticeStats', () {
    test('empty recordings produce zeroed stats', () {
      final s = PracticeStats.from(const [], now: now);
      expect(s.count, 0);
      expect(s.totalSec, 0);
      expect(s.avgScore, 0);
      expect(s.bestScore, 0);
      expect(s.streakDays, 0);
      expect(s.scoreTrend, isEmpty);
      expect(s.groups, isEmpty);
    });

    test('aggregates count, average, best and real attempt duration', () {
      final s = PracticeStats.from([
        _rec(at: daysAgo(0), overall: 70, durationMs: 6500),
        _rec(at: daysAgo(1), overall: 90, durationMs: 0,
            startMs: 0, endMs: 3000),
      ], now: now);
      expect(s.count, 2);
      // 6.5s real attempt + 3s legacy fallback = 9 seconds.
      expect(s.totalSec, 9);
      expect(s.avgScore, 80);
      expect(s.bestScore, 90);
    });

    test('streak counts consecutive days ending today', () {
      final s = PracticeStats.from([
        _rec(at: daysAgo(0)),
        _rec(at: daysAgo(1)),
        _rec(at: daysAgo(2)),
      ], now: now);
      expect(s.streakDays, 3);
    });

    test('streak survives not having practised yet today', () {
      final s = PracticeStats.from([
        _rec(at: daysAgo(1)),
        _rec(at: daysAgo(2)),
      ], now: now);
      expect(s.streakDays, 2);
    });

    test('a gap breaks the streak', () {
      final s = PracticeStats.from([
        _rec(at: daysAgo(1)),
        _rec(at: daysAgo(3)),
      ], now: now);
      expect(s.streakDays, 1);
    });

    test('no practice yesterday either means no active streak', () {
      final s = PracticeStats.from([_rec(at: daysAgo(3))], now: now);
      expect(s.streakDays, 0);
    });

    test('trend is oldest-to-newest and capped at ten points', () {
      final items = [
        for (var i = 1; i <= 12; i++)
          _rec(at: daysAgo(0, hour: 8 + i), overall: 60 + i),
      ];
      final s = PracticeStats.from(items, now: now);
      expect(s.scoreTrend.length, 10);
      // Last ten attempts oldest → newest: attempts 3..12? No — items are
      // newest-first after sort, reversed then take 10 keeps attempts 1..10,
      // i.e. scores 61 (oldest) through 70 (newest of the window).
      expect(s.scoreTrend.first, 61);
      expect(s.scoreTrend.last, 70);
    });

    test('groups days newest first with Chinese labels', () {
      final s = PracticeStats.from([
        _rec(at: daysAgo(0)),
        _rec(at: daysAgo(1)),
      ], now: now);
      expect(s.groups.length, 2);
      expect(s.groups.first.label, '今天');
      expect(s.groups.last.label, '昨天');
    });

    test('older days render as M月d日', () {
      expect(PracticeStats.dayLabel(DateTime(2026, 9, 28), now), '9月28日');
    });
  });
}

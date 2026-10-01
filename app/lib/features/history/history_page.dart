import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/entities/recording.dart';
import '../player/player_controller.dart';
import 'practice_stats.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(practiceRefreshProvider);
    final repo = ref.read(practiceRepositoryProvider);
    final stats = PracticeStats.from(repo.recordings());

    return Scaffold(
      appBar: AppBar(title: const Text('练习履历')),
      body: stats.count == 0
          ? const _EmptyHistory()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                _StatsBoard(stats: stats),
                const SizedBox(height: 12),
                _TrendCard(scores: stats.scoreTrend),
                const SizedBox(height: 12),
                for (final group in stats.groups) ...[
                  _DayHeader(label: group.label, count: group.records.length),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < group.records.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 58),
                          _RecordingTile(
                            recording: group.records[i],
                            onOpen: () => _showDetail(
                                context, ref, group.records[i]),
                            onDelete: () =>
                                _confirmDelete(context, ref, group.records[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Recording r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条跟读记录？'),
        content: const Text('录音文件与评分会一并删除，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(practiceRepositoryProvider).delete(r.id);
      ref.read(practiceRefreshProvider.notifier).state++;
    }
  }

  Future<void> _showDetail(
      BuildContext context, WidgetRef ref, Recording r) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Cover the shell's mini player / navigation bar as well.
      useRootNavigator: true,
      builder: (_) => _RecordingSheet(recording: r),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timeline, size: 56, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('还没有跟读记录\n完成第一次跟读后会出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: () => context.go('/discover'),
            icon: const Icon(Icons.headphones),
            label: const Text('去选一集开始练'),
          ),
        ],
      ),
    );
  }
}

Color scoreColor(int s) {
  if (s >= 85) return Colors.greenAccent;
  if (s >= 70) return Colors.amberAccent;
  return Colors.orangeAccent;
}

class _StatsBoard extends StatelessWidget {
  const _StatsBoard({required this.stats});
  final PracticeStats stats;

  @override
  Widget build(BuildContext context) {
    final minutes = (stats.totalSec / 60).toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            _Stat(value: '${stats.count}', label: '跟读次数'),
            _Stat(value: minutes, label: '练习分钟'),
            _Stat(value: '${stats.avgScore}', label: '平均分'),
            _Stat(
              value: '${stats.streakDays}',
              label: '连续天数',
              icon: Icons.local_fire_department,
              iconColor: Colors.deepOrangeAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (icon != null) ...[
                const SizedBox(width: 2),
                Icon(icon, size: 18, color: iconColor),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.scores});
  final List<int> scores;

  @override
  Widget build(BuildContext context) {
    if (scores.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.show_chart, size: 18, color: Colors.white38),
              SizedBox(width: 8),
              Expanded(
                child: Text('再练 1 次即可生成分数成长曲线',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('成长曲线',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('最近 ${scores.length} 次',
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: CustomPaint(
                size: Size.infinite,
                painter: _SparklinePainter(scores),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.scores);
  final List<int> scores;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.greenAccent.shade400
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.greenAccent.withOpacity(0.25),
          Colors.greenAccent.withOpacity(0.0),
        ],
      ).createShader(Offset.zero & size);
    final grid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;

    // Reference line at 80 points.
    final y80 = size.height * (1 - 80 / 100);
    canvas.drawLine(Offset(0, y80), Offset(size.width, y80), grid);

    double xFor(int i) => scores.length == 1
        ? size.width / 2
        : size.width * i / (scores.length - 1);
    double yFor(int s) => size.height * (1 - (s.clamp(0, 100)) / 100);

    final path = Path();
    for (var i = 0; i < scores.length; i++) {
      final p = Offset(xFor(i), yFor(scores[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(xFor(scores.length - 1), size.height)
      ..lineTo(xFor(0), size.height)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);

    final dot = Paint()..color = Colors.greenAccent.shade400;
    for (var i = 0; i < scores.length; i++) {
      canvas.drawCircle(Offset(xFor(i), yFor(scores[i])), 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.scores != scores;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
      child: Row(
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('$count 次',
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.recording,
    required this.onOpen,
    required this.onDelete,
  });

  final Recording recording;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm');
    return ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: scoreColor(recording.score.overall).withOpacity(0.18),
        child: Text('${recording.score.overall}',
            style: TextStyle(
                fontSize: 13,
                color: scoreColor(recording.score.overall))),
      ),
      title: Text(recording.sentence,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${recording.episodeTitle} · ${fmt.format(recording.createdAt)}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
      ),
    );
  }
}

class _RecordingSheet extends ConsumerWidget {
  const _RecordingSheet({required this.recording});
  final Recording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final isCurrent =
        player.episode?.id == 'recording-${recording.id}';
    final isPlaying = isCurrent && player.isPlaying;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final score = recording.score;
    final seconds = (recording.practiceMs / 1000).toStringAsFixed(1);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      scoreColor(score.overall).withOpacity(0.18),
                  child: Text('${score.overall}',
                      style: TextStyle(
                          color: scoreColor(score.overall),
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recording.episodeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text('${fmt.format(recording.createdAt)} · 录音 $seconds 秒',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(recording.sentence,
                  style: const TextStyle(height: 1.5, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ScoreRing(label: '节奏', value: score.rhythm),
                _ScoreRing(label: '流利', value: score.fluency),
                _ScoreRing(label: '语调', value: score.intonation),
              ],
            ),
            if (score.suggestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...score.suggestions.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                          child: Text(s,
                              style: const TextStyle(
                                  height: 1.4, fontSize: 13))),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: player.loading
                        ? null
                        : () async {
                            if (isCurrent) {
                              await controller.togglePlay();
                            } else {
                              await controller.playRecording(recording);
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                    icon: Icon(isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    label: Text(isPlaying ? '暂停' : '播放录音'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: value / 100,
                strokeWidth: 4,
                backgroundColor: Colors.white12,
              ),
              Text('$value', style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

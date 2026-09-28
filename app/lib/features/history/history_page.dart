import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/entities/recording.dart';

final _refreshHistory = StateProvider<int>((ref) => 0);

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_refreshHistory);
    final repo = ref.read(practiceRepositoryProvider);
    final recordings = repo.recordings();
    final totalSec = repo.totalPracticeSec();

    return Scaffold(
      appBar: AppBar(title: const Text('练习履历')),
      body: recordings.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timeline, size: 56, color: Colors.white24),
                  SizedBox(height: 12),
                  Text('还没有跟读记录\n完成第一次跟读后会出现在这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            )
          : Column(
              children: [
                _StatsBar(totalSec: totalSec, count: recordings.length),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: recordings.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _RecordingTile(
                        recording: recordings[i],
                        onDelete: () async {
                          await repo.delete(recordings[i].id);
                          ref.read(_refreshHistory.notifier).state++;
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.totalSec, required this.count});

  final int totalSec;
  final int count;

  @override
  Widget build(BuildContext context) {
    final minutes = (totalSec / 60).toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat(value: count.toString(), label: '跟读次数'),
            _Stat(value: minutes, label: '练习分钟'),
            _Stat(
                value: (totalSec / count / 60).toStringAsFixed(1),
                label: '次均分钟'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.recording, required this.onDelete});

  final Recording recording;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: _scoreColor(recording.score.overall)
            .withOpacity(0.18),
        child: Text('${recording.score.overall}',
            style: TextStyle(
                fontSize: 13, color: _scoreColor(recording.score.overall))),
      ),
      title: Text(recording.sentence,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${recording.episodeTitle} · ${fmt.format(recording.createdAt)}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
      ),
    );
  }

  Color _scoreColor(int s) {
    if (s >= 85) return Colors.greenAccent;
    if (s >= 70) return Colors.amberAccent;
    return Colors.orangeAccent;
  }
}

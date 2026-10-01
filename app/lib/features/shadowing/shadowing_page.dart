import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/entities/recording.dart';
import '../../domain/entities/transcript.dart';
import '../../pal/pal_providers.dart';
import '../player/player_controller.dart';
import 'shadow_scorer.dart';

class ShadowingPage extends ConsumerStatefulWidget {
  const ShadowingPage({super.key});

  @override
  ConsumerState<ShadowingPage> createState() => _ShadowingPageState();
}

class _ShadowingPageState extends ConsumerState<ShadowingPage> {
  DateTime? _recordStart;
  bool _busy = false;
  bool _recording = false;
  PronunciationScore? _lastScore;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final segment = controller.currentSegment();

    return Scaffold(
      appBar: AppBar(title: const Text('影子跟读')),
      body: segment == null
          ? const Center(
              child: Text('播放器中没有可跟读的句子，请先选择一集内容'),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SentenceCard(segment: segment, rate: player.rate),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await controller
                              .seek(segment.startOffset);
                          await controller.togglePlay();
                        },
                        icon: const Icon(Icons.headphones),
                        label: const Text('听原声'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            controller.toggleSentenceLoop(segment),
                        icon: Icon(player.loopEnabled
                            ? Icons.repeat_one
                            : Icons.repeat),
                        label: Text(player.loopEnabled ? '取消循环' : '单句循环'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _RecordButton(
                    busy: _busy,
                    recording: _recording,
                    onRecord: () => _toggleRecording(segment),
                  ),
                  const SizedBox(height: 12),
                  if (_lastScore != null) _ScoreCard(score: _lastScore!),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Future<void> _toggleRecording(TranscriptSegment segment) async {
    final recorder = ref.read(audioRecorderServiceProvider);
    if (_recording) {
      setState(() => _busy = true);
      final path = await recorder.stop();
      final attempt = DateTime.now().difference(_recordStart!);
      final score = const ShadowScorer().score(
        reference: segment.endOffset - segment.startOffset,
        attempt: attempt,
        pauseCount: 0,
      );
      final recording = Recording(
        id: 'rec-${DateTime.now().millisecondsSinceEpoch}',
        episodeTitle:
            ref.read(playerControllerProvider).episode?.title ?? '',
        sentence: segment.text,
        startMs: segment.startOffset.inMilliseconds,
        endMs: segment.endOffset.inMilliseconds,
        durationMs: attempt.inMilliseconds,
        filePath: path,
        score: score,
        createdAt: DateTime.now(),
      );
      await ref.read(practiceRepositoryProvider).save(recording);
      ref.read(practiceRefreshProvider.notifier).state++;
      if (!mounted) return;
      setState(() {
        _lastScore = score;
        _busy = false;
        _recording = false;
        _recordStart = null;
      });
    } else {
      final granted = await recorder.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能跟读录音')),
          );
        }
        return;
      }
      await recorder.start();
      setState(() {
        _recordStart = DateTime.now();
        _recording = true;
      });
    }
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({required this.segment, required this.rate});

  final TranscriptSegment segment;
  final double rate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over, size: 18),
                const SizedBox(width: 6),
                Text('当前句 · 语速 ${rate}x',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(segment.text,
                style: const TextStyle(
                    fontSize: 20, height: 1.5, fontWeight: FontWeight.w600)),
            if (segment.translation != null) ...[
              const SizedBox(height: 8),
              Text(segment.translation!,
                  style: const TextStyle(color: Colors.white60, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.busy,
    required this.recording,
    required this.onRecord,
  });

  final bool busy;
  final bool recording;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: busy ? null : onRecord,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: recording ? 88 : 80,
            height: recording ? 88 : 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording
                  ? Colors.red.withOpacity(0.85)
                  : Theme.of(context).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: (recording ? Colors.red : Theme.of(context)
                          .colorScheme.primary)
                      .withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          busy
              ? '评分中…'
              : recording
                  ? '点击停止并评分'
                  : '点击开始跟读',
          style: const TextStyle(color: Colors.white60),
        ),
      ],
    );
  }

}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score});
  final PronunciationScore score;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${score.overall}',
                    style: Theme.of(context).textTheme.headlineMedium),
                const Text(' 分', style: TextStyle(fontSize: 14)),
                const Spacer(),
                _MiniBar(label: '节奏', value: score.rhythm),
                _MiniBar(label: '流利', value: score.fluency),
                _MiniBar(label: '语调', value: score.intonation),
              ],
            ),
            const SizedBox(height: 10),
            ...score.suggestions.map(
              (s) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(s, style: const TextStyle(height: 1.4))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: value / 100,
                  strokeWidth: 3,
                  backgroundColor: Colors.white12,
                ),
                Text('$value', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

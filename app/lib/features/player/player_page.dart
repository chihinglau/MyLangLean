import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import 'player_controller.dart';
import 'widgets/karaoke_subtitle.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes ~/ 60 > 0 ? '${d.inMinutes ~/ 60}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);

    if (!state.hasMedia) {
      return const Scaffold(
        body: Center(child: Text('请先在「发现」或「资料库」选择内容')),
      );
    }

    final total = controller.mediaDuration;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.episode!.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15)),
            Text(state.episode!.podcastTitle ?? '本地内容',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
      body: Column(
        children: [
          _Header(title: state.episode!.title, loading: state.loading),
          if (state.mediaError != null && !state.loading)
            Expanded(child: _MediaErrorView(message: state.mediaError!))
          else if (state.transcript != null)
            Expanded(
              child: KaraokeSubtitle(
                transcript: state.transcript!,
                position: controller.position,
                mode: state.mode,
                fontScale: state.fontScale,
                loopEnabled: state.loopEnabled,
                onSeekWord: (sec) => controller
                    .seek(Duration(milliseconds: (sec * 1000).round())),
                onToggleLoop: (seg) => controller.toggleSentenceLoop(seg),
              ),
            )
          else
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.transcriptLoading
                      ? const _TranscriptLoading()
                      : _SubtitleUnavailable(error: state.transcriptError),
            ),
          _ProgressBar(
            position: controller.position,
            total: total,
            fmt: _fmt,
            onSeek: controller.seek,
          ),
          _Controls(state: state, controller: controller),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SubtitleUnavailable extends StatelessWidget {
  const _SubtitleUnavailable({this.error});

  /// Null = no paired subtitle; non-null = paired file broken/unreadable.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final broken = error != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(broken ? Icons.error_outline : Icons.subtitles_off,
                size: 52, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              broken ? '字幕无法使用' : '这段内容还没有字幕',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              broken
                  ? '$error\n可在「我的内容」中重新关联字幕文件'
                  : '可在电脑上用「字幕工坊」生成字幕，\n再到「我的内容」导入或关联字幕文件',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptLoading extends StatelessWidget {
  const _TranscriptLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('正在为你生成逐词字幕…',
                style: TextStyle(fontSize: 16, color: Colors.white70)),
            SizedBox(height: 8),
            Text('可以先听音频，字幕准备好后自动显示',
                style: TextStyle(fontSize: 13, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

class _MediaErrorView extends StatelessWidget {
  const _MediaErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 52, color: Colors.white24),
            const SizedBox(height: 14),
            const Text('媒体无法播放',
                style: TextStyle(fontSize: 16, color: Colors.white70)),
            const SizedBox(height: 8),
            Text('$message\n请确认文件未被删除或移动，且为设备支持的音视频格式',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white38)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.loading});
  final String title;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.25),
            Theme.of(context).colorScheme.secondary.withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('逐词字幕 · 影子跟读',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  loading ? '正在生成同步字幕…' : '点词定位 · 点循环按钮练难句',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({
    required this.position,
    required this.total,
    required this.fmt,
    required this.onSeek,
  });

  final ValueNotifier<Duration> position;
  final Duration total;
  final String Function(Duration) fmt;
  final ValueChanged<Duration> onSeek;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  /// Non-null while the user is dragging: the slider tracks this local
  /// value and must NOT issue native seeks for every intermediate frame.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.position,
      builder: (context, pos, _) {
        final totalMs = widget.total.inMilliseconds;
        final max = totalMs.clamp(1, 1 << 31).toDouble();
        final live = pos.inMilliseconds.clamp(0, totalMs).toDouble();
        final cur = (_dragValue ?? live).clamp(0, max).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Text(widget.fmt(Duration(milliseconds: cur.round())),
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white54)),
              Expanded(
                child: Slider(
                  value: cur,
                  max: max,
                  onChangeStart: (v) => setState(() => _dragValue = v),
                  onChanged: (v) => setState(() => _dragValue = v),
                  onChangeEnd: (v) {
                    setState(() => _dragValue = null);
                    widget.onSeek(
                        Duration(milliseconds: v.round()));
                  },
                ),
              ),
              Text(widget.fmt(widget.total),
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white54)),
            ],
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.controller});

  final PlayerState state;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '后退 5 秒',
                iconSize: 30,
                onPressed: () =>
                    controller.seekBy(const Duration(seconds: -5)),
                icon: const Icon(Icons.replay_5),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: controller.togglePlay,
                child: Icon(state.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '前进 5 秒',
                iconSize: 30,
                onPressed: () =>
                    controller.seekBy(const Duration(seconds: 5)),
                icon: const Icon(Icons.forward_5),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final picked = await showModalBottomSheet<double>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => _RateSheet(current: state.rate),
                  );
                  if (picked != null) controller.setRate(picked);
                },
                icon: const Icon(Icons.speed, size: 19),
                label: Text('${state.rate}x'),
              ),
              TextButton.icon(
                onPressed: controller.cycleSubtitleMode,
                icon: Icon(
                  switch (state.mode) {
                    SubtitleMode.sourceOnly => Icons.subtitles_outlined,
                    SubtitleMode.bilingual => Icons.closed_caption,
                    SubtitleMode.hidden => Icons.visibility_off,
                  },
                  size: 19,
                ),
                label: Text(switch (state.mode) {
                  SubtitleMode.sourceOnly => '原文',
                  SubtitleMode.bilingual => '双语',
                  SubtitleMode.hidden => '盲听',
                }),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showModalBottomSheet<double>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => _FontSheet(current: state.fontScale),
                  );
                  if (picked != null) controller.setFontScale(picked);
                },
                icon: const Icon(Icons.format_size, size: 19),
                label: Text('${state.fontScale}x'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.push('/shadowing'),
                icon: const Icon(Icons.mic, size: 19),
                label: const Text('跟读'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RateSheet extends StatelessWidget {
  const _RateSheet({required this.current});
  final double current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: Env.playRates
            .map((r) => RadioListTile<double>(
                  value: r,
                  groupValue: current,
                  title: Text('$r x'),
                  onChanged: (v) => Navigator.pop(context, v),
                ))
            .toList(),
      ),
    );
  }
}

class _FontSheet extends StatelessWidget {
  const _FontSheet({required this.current});
  final double current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: Env.fontScales
            .map((f) => RadioListTile<double>(
                  value: f,
                  groupValue: current,
                  title: Text('字号 ${f}x'),
                  onChanged: (v) => Navigator.pop(context, v),
                ))
            .toList(),
      ),
    );
  }
}

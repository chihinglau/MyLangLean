import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../../domain/entities/transcript.dart';
import '../player_controller.dart';

/// Karaoke-style word-by-word subtitle list.
///
/// * active word is highlighted from the 20-30Hz position tick
/// * tap a word to seek
/// * tap the loop icon to A/B-repeat a sentence
/// * auto-centres the active sentence (pauses for 3s after manual scrolling)
class KaraokeSubtitle extends StatefulWidget {
  const KaraokeSubtitle({
    super.key,
    required this.transcript,
    required this.position,
    required this.mode,
    required this.fontScale,
    required this.loopEnabled,
    required this.onSeekWord,
    required this.onToggleLoop,
  });

  final Transcript transcript;
  final ValueNotifier<Duration> position;
  final SubtitleMode mode;
  final double fontScale;
  final bool loopEnabled;
  final void Function(double seconds) onSeekWord;
  final void Function(TranscriptSegment) onToggleLoop;

  @override
  State<KaraokeSubtitle> createState() => _KaraokeSubtitleState();
}

class _KaraokeSubtitleState extends State<KaraokeSubtitle> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _activeSegment = -1;
  DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant KaraokeSubtitle old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onTick);
      widget.position.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onTick);
    _scroll.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = widget.transcript;
    final sec = widget.position.value.inMilliseconds / 1000.0;
    final idx = t.index.segmentAt(sec, t.segments);
    if (idx != _activeSegment) {
      _activeSegment = idx;
      _ensureVisible(idx);
    }
    if (mounted) setState(() {});
  }

  void _ensureVisible(int idx) {
    if (!_scroll.hasClients) return;
    final idleFor =
        DateTime.now().difference(_lastUserScroll).inMilliseconds;
    if (idleFor < 3000) return;
    final ctx = _keys[idx]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.35,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == SubtitleMode.hidden) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('盲听模式 · 试着不看字幕听懂这一句',
              style: TextStyle(color: Colors.white38)),
        ),
      );
    }

    final theme = Theme.of(context);
    final sec = widget.position.value.inMilliseconds / 1000.0;
    final activeWord = widget.transcript.index.wordAt(sec);
    final segments = widget.transcript.segments;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification &&
            n.direction != ScrollDirection.idle) {
          _lastUserScroll = DateTime.now();
        }
        return false;
      },
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          itemCount: segments.length,
          itemBuilder: (context, i) {
            final seg = segments[i];
            final key = _keys.putIfAbsent(i, GlobalKey.new);
            final isActive = i == _activeSegment;
            return Container(
              key: key,
              margin: const EdgeInsets.only(bottom: 22),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary.withOpacity(0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: isActive
                    ? Border.all(
                        color:
                            theme.colorScheme.primary.withOpacity(0.35))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildWords(theme, seg, activeWord)),
                      _LoopButton(
                        active: widget.loopEnabled && isActive,
                        onTap: () => widget.onToggleLoop(seg),
                      ),
                    ],
                  ),
                  if (widget.mode == SubtitleMode.bilingual &&
                      seg.translation != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      seg.translation!,
                      style: TextStyle(
                        fontSize: 14 * widget.fontScale,
                        color: Colors.white60,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWords(
      ThemeData theme, TranscriptSegment seg, FlatWord? activeWord) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < seg.words.length; i++) {
      final word = seg.words[i];
      final isActive = activeWord != null &&
          activeWord.segmentId == seg.id &&
          activeWord.wordIndex == i;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => widget.onSeekWord(word.s),
          child: Text(
            '${word.w}${i == seg.words.length - 1 ? '' : ' '}',
            style: TextStyle(
              fontSize: 19 * widget.fontScale,
              height: 1.55,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
              color: isActive
                  ? theme.colorScheme.secondary
                  : Colors.white.withOpacity(0.88),
              backgroundColor: isActive
                  ? theme.colorScheme.primary.withOpacity(0.28)
                  : Colors.transparent,
            ),
          ),
        ),
      ));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _LoopButton extends StatelessWidget {
  const _LoopButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '单句循环',
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(active ? Icons.repeat_one : Icons.repeat,
          size: 20,
          color: active
              ? Theme.of(context).colorScheme.secondary
              : Colors.white38),
    );
  }
}

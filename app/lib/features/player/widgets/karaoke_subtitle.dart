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
  bool _noTranslationBannerDismissed = false;
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
      return _BlindListenView(
        transcript: widget.transcript,
        position: widget.position,
        fontScale: widget.fontScale,
        loopEnabled: widget.loopEnabled,
        onToggleLoop: widget.onToggleLoop,
      );
    }

    final theme = Theme.of(context);
    final sec = widget.position.value.inMilliseconds / 1000.0;
    final activeWord = widget.transcript.index.wordAt(sec);
    final segments = widget.transcript.segments;
    final bilingual = widget.mode == SubtitleMode.bilingual;
    // 0 translations  -> one dismissible banner, no per-line noise.
    // Some translations -> every untranslated line gets a dim placeholder.
    final noneTranslated = bilingual && !widget.transcript.hasTranslations;
    final partiallyTranslated = bilingual &&
        widget.transcript.hasTranslations &&
        widget.transcript.translatedCount < segments.length;

    return Column(
      children: [
        if (noneTranslated && !_noTranslationBannerDismissed)
          _NoTranslationBanner(
            onDismiss: () =>
                setState(() => _noTranslationBannerDismissed = true),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                itemCount: segments.length,
                itemBuilder: (context, i) {
                  final seg = segments[i];
                  final key = _keys.putIfAbsent(i, GlobalKey.new);
                  final isActive = i == _activeSegment;
                  return Container(
                    key: key,
                    margin: const EdgeInsets.only(bottom: 22),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.colorScheme.primary.withOpacity(0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: isActive
                          ? Border.all(
                              color: theme.colorScheme.primary
                                  .withOpacity(0.35))
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: _buildWords(theme, seg, activeWord)),
                            _LoopButton(
                              active: widget.loopEnabled && isActive,
                              onTap: () => widget.onToggleLoop(seg),
                            ),
                          ],
                        ),
                        if (bilingual && seg.hasTranslation) ...[
                          const SizedBox(height: 6),
                          Text(
                            seg.translation!,
                            style: TextStyle(
                              fontSize: 14 * widget.fontScale,
                              color: Colors.white60,
                              height: 1.45,
                            ),
                          ),
                        ] else if (partiallyTranslated) ...[
                          // Only a few sentences miss glosses: mark them in
                          // place so the gap is visible instead of silently
                          // degrading bilingual mode to source-only.
                          const SizedBox(height: 6),
                          Text(
                            '（暂无译文，可用字幕工坊补译后重新关联）',
                            style: TextStyle(
                              fontSize: 12 * widget.fontScale,
                              fontStyle: FontStyle.italic,
                              color: Colors.white24,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
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

/// Shown in bilingual mode when the loaded transcript carries no
/// translations at all (produced before the studio gained one-click
/// translation). Without it bilingual mode silently degraded to source-only.
class _NoTranslationBanner extends StatelessWidget {
  const _NoTranslationBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.translate, size: 18,
              color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '当前字幕没有译文，双语模式暂只显示原文。'
              '可在电脑端「字幕工坊」一键翻译后重新关联字幕。',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blind-listening trainer. Subtitles stay hidden; the learner reveals the
/// currently playing sentence on demand, can peek at its gloss, and A/B-loop
/// it for intensive listening.
class _BlindListenView extends StatefulWidget {
  const _BlindListenView({
    required this.transcript,
    required this.position,
    required this.fontScale,
    required this.loopEnabled,
    required this.onToggleLoop,
  });

  final Transcript transcript;
  final ValueNotifier<Duration> position;
  final double fontScale;
  final bool loopEnabled;
  final void Function(TranscriptSegment) onToggleLoop;

  @override
  State<_BlindListenView> createState() => _BlindListenViewState();
}

class _BlindListenViewState extends State<_BlindListenView> {
  bool _revealed = false;
  bool _showGloss = false;
  int _lastSegment = -1;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _BlindListenView old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onTick);
      widget.position.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!_revealed || !mounted) return;
    final idx = _activeIndex();
    if (idx != _lastSegment) {
      // Each new sentence starts hidden again; the gloss peeker resets too.
      _lastSegment = idx;
      _showGloss = false;
    }
    setState(() {});
  }

  int _activeIndex() {
    final segs = widget.transcript.segments;
    if (segs.isEmpty) return -1;
    final sec = widget.position.value.inMilliseconds / 1000.0;
    return widget.transcript.index.segmentAt(sec, segs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idx = _activeIndex();
    final seg = idx >= 0 ? widget.transcript.segments[idx] : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off_outlined,
                size: 40, color: Colors.white24),
            const SizedBox(height: 14),
            const Text('盲听模式 · 先不看字幕，试着听懂这一句',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 22),
            if (_revealed && seg != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seg.text,
                      style: TextStyle(
                        fontSize: 20 * widget.fontScale,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    if (_showGloss && seg.hasTranslation) ...[
                      const SizedBox(height: 8),
                      Text(
                        seg.translation!,
                        style: TextStyle(
                          fontSize: 14 * widget.fontScale,
                          color: Colors.white60,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (seg.hasTranslation)
                          TextButton(
                            onPressed: () => setState(
                                () => _showGloss = !_showGloss),
                            child: Text(_showGloss ? '隐藏译文' : '看译文'),
                          ),
                        _LoopButton(
                          active: widget.loopEnabled,
                          onTap: () => widget.onToggleLoop(seg),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _revealed = false;
                            _showGloss = false;
                          }),
                          child: const Text('继续盲听'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else
              FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _revealed = true;
                  _lastSegment = _activeIndex();
                }),
                icon: const Icon(Icons.visibility),
                label: const Text('显示当前句'),
              ),
          ],
        ),
      ),
    );
  }
}

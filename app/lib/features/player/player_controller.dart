import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/mock_repositories.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/recording.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/entities/user_preferences.dart';
import '../../pal/audio_player_service.dart';
import '../../pal/pal_providers.dart';

enum SubtitleMode {
  /// Source + karaoke highlight
  sourceOnly,

  /// Source highlight + translation line
  bilingual,

  /// Hide subtitles (blind listening)
  hidden,
}

class PlayerState {
  const PlayerState({
    this.episode,
    this.transcript,
    this.transcriptError,
    this.mediaError,
    this.isPlaying = false,
    this.rate = 1.0,
    this.loopEnabled = false,
    this.mode = SubtitleMode.bilingual,
    this.fontScale = 1.0,
    this.loading = false,
    this.transcriptLoading = false,
  });

  final Episode? episode;
  final Transcript? transcript;

  /// Non-null when a paired subtitle file exists but cannot be used.
  /// Null transcript + null error = media simply has no subtitles.
  final String? transcriptError;

  /// Non-null when the audio/video file itself cannot be opened or decoded.
  final String? mediaError;
  final bool isPlaying;
  final double rate;
  final bool loopEnabled;
  final SubtitleMode mode;
  final double fontScale;
  final bool loading;

  /// True while an on-demand transcript is being generated in background.
  final bool transcriptLoading;

  bool get hasMedia => episode != null;

  PlayerState copyWith({
    Episode? episode,
    Transcript? transcript,
    String? transcriptError,
    String? mediaError,
    bool? isPlaying,
    double? rate,
    bool? loopEnabled,
    SubtitleMode? mode,
    double? fontScale,
    bool? loading,
    bool? transcriptLoading,
  }) {
    return PlayerState(
      episode: episode ?? this.episode,
      transcript: transcript ?? this.transcript,
      transcriptError: transcriptError ?? this.transcriptError,
      mediaError: mediaError ?? this.mediaError,
      isPlaying: isPlaying ?? this.isPlaying,
      rate: rate ?? this.rate,
      loopEnabled: loopEnabled ?? this.loopEnabled,
      mode: mode ?? this.mode,
      fontScale: fontScale ?? this.fontScale,
      loading: loading ?? this.loading,
      transcriptLoading: transcriptLoading ?? this.transcriptLoading,
    );
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

class PlayerController extends Notifier<PlayerState> {
  late final AudioPlayerService _audio;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String>? _errorSub;

  /// Bumped on every playEpisode; stale completions from a previous episode
  /// are discarded when two plays interleave.
  int _playToken = 0;

  /// Position ticks live outside Notifier state to avoid rebuilding the
  /// whole widget tree at 20-30Hz. Karaoke widgets listen locally.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  @override
  PlayerState build() {
    _audio = ref.watch(audioPlayerServiceProvider);
    _posSub = _audio.positionStream.listen((p) => position.value = p);
    _playingSub = _audio.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _errorSub = _audio.errorStream.listen((message) {
      state = state.copyWith(
        isPlaying: false,
        loading: false,
        mediaError: '音频无法播放：文件缺失或编码不受支持（$message）',
      );
    });
    ref.onDispose(() {
      _posSub?.cancel();
      _playingSub?.cancel();
      _errorSub?.cancel();
      position.dispose();
    });

    // Profile-page preferences become playback defaults; later edits apply
    // live without rebuilding the audio subscriptions.
    final prefs = ref.read(preferencesProvider);
    ref.listen(preferencesProvider, (prev, next) {
      if (prev?.defaultRate != next.defaultRate && state.hasMedia) {
        _audio.setRate(next.defaultRate);
      }
      state = state.copyWith(
        rate: next.defaultRate,
        fontScale: next.defaultFontScale,
        mode: _mapSubtitleMode(next.subtitle),
      );
    });
    return PlayerState(
      rate: prefs.defaultRate,
      fontScale: prefs.defaultFontScale,
      mode: _mapSubtitleMode(prefs.subtitle),
    );
  }

  static SubtitleMode _mapSubtitleMode(SubtitlePref pref) =>
      switch (pref) {
        SubtitlePref.sourceOnly => SubtitleMode.sourceOnly,
        SubtitlePref.bilingual => SubtitleMode.bilingual,
        SubtitlePref.hidden => SubtitleMode.hidden,
      };

  /// Whether the player is currently showing a history recording rather
  /// than a regular episode.
  bool isPlayingRecording(String recordingId) =>
      state.episode?.id == 'recording-$recordingId';

  /// Plays back a shadowing attempt from the history page through the same
  /// audio pipeline (and mini player) as normal episodes.
  Future<void> playRecording(Recording recording) async {
    final episode = Episode(
      id: 'recording-${recording.id}',
      title: recording.sentence.isEmpty ? '跟读录音' : recording.sentence,
      audioUrl: recording.filePath,
      isLocal: true,
      localPath: recording.filePath,
      duration: Duration(milliseconds: recording.practiceMs),
    );
    await playEpisode(episode);
  }

  /// Loads and starts [episode]'s audio immediately, then resolves its
  /// transcript in the background (on-demand ASR can take a while and must
  /// never block playback). Missing subtitles never block audio; broken
  /// ones surface as [PlayerState.transcriptError].
  Future<void> playEpisode(Episode episode) async {
    final token = ++_playToken;
    state = PlayerState(
      episode: episode,
      loading: true,
      rate: state.rate,
      mode: state.mode,
      fontScale: state.fontScale,
    );
    position.value = Duration.zero;

    String? mediaError;
    try {
      await _audio.load(episode.playableSource, isLocal: episode.isLocal);
      await _audio.setRate(state.rate);
    } catch (e) {
      mediaError = '音频无法加载：文件可能已被删除或移动';
    }
    if (token != _playToken) return;
    state = state.copyWith(mediaError: mediaError, loading: false);
    if (mediaError != null) return;
    await _audio.play();
    unawaited(_resolveTranscript(episode, token));
  }

  Future<void> _resolveTranscript(Episode episode, int token) async {
    state = state.copyWith(transcriptLoading: true);
    try {
      final t =
          await ref.read(transcriptRepositoryProvider).transcriptFor(episode);
      if (token != _playToken) return;
      state = state.copyWith(transcript: t, transcriptLoading: false);
    } catch (e) {
      if (token != _playToken) return;
      state = state.copyWith(
        transcriptLoading: false,
        transcriptError:
            e is TranscriptException ? e.message : '字幕加载失败',
      );
    }
  }

  /// Duration used for progress display/seeking. Normally the transcript
  /// and the media metadata agree; when they don't (partial/stub
  /// transcript), take the longer one so the progress bar never clips
  /// audio that is actually longer.
  Duration get mediaDuration {
    final transcriptLen =
        state.transcript?.totalDuration ?? Duration.zero;
    final mediaLen = _audio.duration;
    return transcriptLen > mediaLen ? transcriptLen : mediaLen;
  }

  Future<void> togglePlay() async {
    if (!state.hasMedia) return;
    if (state.isPlaying) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  Future<void> seek(Duration p) async {
    final clamped = Duration(
        milliseconds:
            p.inMilliseconds.clamp(0, mediaDuration.inMilliseconds));
    // Optimistic UI: move the play head (and karaoke highlight) immediately
    // instead of waiting for the async native seek + first position tick
    // (which can lag seconds when the target is outside the cached prefix).
    position.value = clamped;
    await _audio.seekTo(clamped);
  }

  Future<void> seekBy(Duration delta) async {
    await seek(position.value + delta);
  }

  Future<void> setRate(double rate) async {
    await _audio.setRate(rate);
    state = state.copyWith(rate: rate);
  }

  /// Repeat a single sentence; tap again to clear.
  Future<void> toggleSentenceLoop(TranscriptSegment segment) async {
    if (state.loopEnabled) {
      await _audio.setLoopSegment();
      state = state.copyWith(loopEnabled: false);
    } else {
      await _audio.setLoopSegment(a: segment.startOffset, b: segment.endOffset);
      await _audio.seekTo(segment.startOffset);
      state = state.copyWith(loopEnabled: true);
    }
  }

  void cycleSubtitleMode() {
    final next = SubtitleMode.values[
        (state.mode.index + 1) % SubtitleMode.values.length];
    state = state.copyWith(mode: next);
  }

  void setFontScale(double scale) => state = state.copyWith(fontScale: scale);

  /// Segment currently under the play head (for shadowing page).
  TranscriptSegment? currentSegment() {
    final t = state.transcript;
    if (t == null) return null;
    final sec = position.value.inMilliseconds / 1000.0;
    return t.segments[t.index.segmentAt(sec, t.segments)];
  }
}

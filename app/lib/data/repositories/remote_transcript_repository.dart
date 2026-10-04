import 'dart:async';

import '../../domain/entities/episode.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/repositories/repositories.dart';
import '../kv_store.dart';
import '../remote/ml_api.dart';
import 'mock_repositories.dart';

/// Online transcript resolution:
///   * imported local media / bundled samples -> [LocalAwareTranscriptRepository]
///     (sidecar JSON or the bundled sample transcript);
///   * catalog episodes -> server-side on-demand ASR via
///     `/api/v1/transcriptions` (billed against the monthly quota).
///
/// Results are cached in memory and in the [KvStore], so replays of the
/// same episode never trigger a second transcription/charge. The server's
/// TranscriptOut JSON already matches [Transcript.fromJson] (shared frozen
/// schema), hence no field remapping is needed.
class RemoteTranscriptRepository implements TranscriptRepository {
  RemoteTranscriptRepository(
    this._api, {
    TranscriptRepository? local,
    KvStore? kv,
    Duration pollInterval = const Duration(milliseconds: 1500),
    Duration timeout = const Duration(minutes: 10),
  })  : _local = local ?? LocalAwareTranscriptRepository(),
        _kv = kv,
        _pollInterval = pollInterval,
        _timeout = timeout;

  final MlApi _api;
  final TranscriptRepository _local;
  final KvStore? _kv;
  final Duration _pollInterval;
  final Duration _timeout;

  static const _cachePrefix = 'cache.transcript.';
  final Map<String, Transcript> _mem = {};

  @override
  Future<Transcript?> transcriptFor(Episode episode) async {
    final source = episode.playableSource;
    if (episode.isLocal ||
        episode.transcriptPath != null ||
        source.startsWith('asset://')) {
      return _local.transcriptFor(episode);
    }
    if (source.isEmpty) return null;

    final cached = _lookup(episode.id);
    if (cached != null) return cached;

    // 服务器已随该单集一起发布的双语字幕：直接使用，不触发按需 ASR、
    // 不扣月度转录额度。
    final published = episode.transcript;
    if (published != null) {
      _store(episode.id, published);
      return published;
    }

    final job = await _api.createTranscription(
      audioUrl: source,
      language: episode.language,
      clientKey: 'ep-${episode.id}',
    );
    final done = await _awaitDone(job.id);
    if (done.isError || done.transcript == null) {
      throw TranscriptException(_friendlyError(done.error));
    }
    final transcript = Transcript.fromJson(done.transcript!);
    _store(episode.id, transcript);
    return transcript;
  }

  Future<RemoteTranscriptionJob> _awaitDone(String id) async {
    final deadline = DateTime.now().add(_timeout);
    var job = RemoteTranscriptionJob(id: id, status: 'queued');
    while (!job.isDone && !job.isError) {
      if (DateTime.now().isAfter(deadline)) {
        throw TranscriptException('字幕生成超时，请稍后重试');
      }
      await Future<void>.delayed(_pollInterval);
      job = await _api.transcriptionJob(id);
    }
    return job;
  }

  String _friendlyError(String? raw) {
    final text = raw ?? '';
    if (text.contains('quota')) {
      return '本月转录额度已用完，可在「我的」页查看额度';
    }
    return text.isNotEmpty ? '字幕生成失败：$text' : '字幕生成失败，请稍后重试';
  }

  // ---- cache --------------------------------------------------------------

  Transcript? _lookup(String episodeId) {
    final mem = _mem[episodeId];
    if (mem != null) return mem;
    final raw = _kv?.get('$_cachePrefix$episodeId');
    if (raw is Map) {
      final t = Transcript.fromJson(Map<String, dynamic>.from(raw));
      _mem[episodeId] = t;
      return t;
    }
    return null;
  }

  void _store(String episodeId, Transcript transcript) {
    _mem[episodeId] = transcript;
    unawaited(_kv?.set('$_cachePrefix$episodeId', _toJson(transcript)));
  }

  /// Transcript has no toJson yet; serialize through the shared frozen
  /// schema fields here.
  static Map<String, dynamic> _toJson(Transcript t) => {
        'version': t.version,
        'language': t.language,
        'duration': t.duration,
        'segments': [
          for (final s in t.segments)
            {
              'id': s.id,
              'start': s.start,
              'end': s.end,
              'text': s.text,
              if (s.translation != null) 'translation': s.translation,
              'words': [
                for (final w in s.words)
                  {
                    'w': w.w,
                    's': w.s,
                    'e': w.e,
                    if (w.p != null) 'p': w.p,
                  },
              ],
            },
        ],
      };
}

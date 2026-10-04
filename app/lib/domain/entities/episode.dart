import 'transcript.dart';

/// A playable episode or a locally imported media file.
class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.audioUrl,
    this.podcastId,
    this.podcastTitle,
    this.artworkUrl,
    this.duration = Duration.zero,
    this.pubDate,
    this.isLocal = false,
    this.localPath,
    this.transcriptPath,
    this.transcript,
    this.language = 'en',
  });

  final String id;
  final String title;
  final String? podcastId;
  final String? podcastTitle;
  final String? artworkUrl;
  final String audioUrl;
  final Duration duration;
  final DateTime? pubDate;
  final bool isLocal;
  final String? localPath;

  /// Absolute path of a sidecar word-level transcript JSON imported by the
  /// user (produced by the Windows Subtitle Studio). null = no paired file.
  final String? transcriptPath;

  /// Word-level bilingual transcript published together with this episode
  /// by the server (sourced from the catalog episodes payload). null = the
  /// episode has no server-published transcript; the player may fall back
  /// to on-demand ASR.
  final Transcript? transcript;

  final String language;

  /// Source handed to the player: sandbox path for local files, URL otherwise.
  String get playableSource => isLocal ? (localPath ?? audioUrl) : audioUrl;

  bool get hasTranscriptFile => transcriptPath != null;

  Episode copyWith({
    String? title,
    Duration? duration,
    String? localPath,
    String? transcriptPath,
    String? language,
  }) =>
      Episode(
        id: id,
        title: title ?? this.title,
        podcastId: podcastId,
        podcastTitle: podcastTitle,
        artworkUrl: artworkUrl,
        audioUrl: audioUrl,
        duration: duration ?? this.duration,
        pubDate: pubDate,
        isLocal: isLocal,
        localPath: localPath ?? this.localPath,
        transcriptPath: transcriptPath ?? this.transcriptPath,
        transcript: transcript,
        language: language ?? this.language,
      );

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        podcastId: json['podcastId'] as String?,
        podcastTitle: json['podcastTitle'] as String?,
        artworkUrl: json['artworkUrl'] as String?,
        audioUrl: json['audioUrl'] as String? ?? '',
        duration:
            Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
        pubDate: json['pubDate'] == null
            ? null
            : DateTime.tryParse(json['pubDate'] as String),
        isLocal: json['isLocal'] as bool? ?? false,
        localPath: json['localPath'] as String?,
        transcriptPath: json['transcriptPath'] as String?,
        transcript: json['transcript'] is Map
            ? Transcript.fromJson(
                Map<String, dynamic>.from(json['transcript'] as Map))
            : null,
        language: json['language'] as String? ?? 'en',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'podcastId': podcastId,
        'podcastTitle': podcastTitle,
        'artworkUrl': artworkUrl,
        'audioUrl': audioUrl,
        'durationMs': duration.inMilliseconds,
        'pubDate': pubDate?.toIso8601String(),
        'isLocal': isLocal,
        'localPath': localPath,
        'transcriptPath': transcriptPath,
        if (transcript != null) 'transcript': transcriptToJson(transcript!),
        'language': language,
      };
}

/// Serialize a [Transcript] with the shared frozen schema fields. Kept here
/// (rather than on the entity) because [Transcript] is shared read-only across
/// platforms; mirrors the fields consumed by `Transcript.fromJson`.
Map<String, dynamic> transcriptToJson(Transcript t) => {
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

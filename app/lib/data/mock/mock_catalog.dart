import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';

/// Offline demo catalog. Replaced by iTunes/PodcastIndex + RSS in production.
class MockCatalog {
  static const List<Podcast> podcasts = [
    Podcast(
      id: 'p1',
      title: 'Real English Voices',
      author: 'Language Lab',
      feedUrl: 'https://example.com/feeds/real-english-voices.xml',
      language: 'en',
      level: ContentLevel.beginner,
      description: '真实语速的日常英语对话，适合逐句精听与跟读。',
    ),
    Podcast(
      id: 'p2',
      title: 'Tokyo Street Stories',
      author: 'Go! Go! Nihon',
      feedUrl: 'https://example.com/feeds/tokyo-street-stories.xml',
      language: 'ja',
      level: ContentLevel.intermediate,
      description: '东京街头实景录音，旅行日语听力与影子跟读。',
    ),
    Podcast(
      id: 'p3',
      title: 'Coffee Break French',
      author: 'Radio Lingua',
      feedUrl: 'https://example.com/feeds/coffee-break-french.xml',
      language: 'fr',
      level: ContentLevel.beginner,
      description: '一杯咖啡时间的法语短节目，发音清晰。',
    ),
    Podcast(
      id: 'p4',
      title: 'Slow German News',
      level: ContentLevel.advanced,
      author: 'Nachrichten Langsam',
      feedUrl: 'https://example.com/feeds/slow-german-news.xml',
      language: 'de',
      description: '慢速德语新闻，适合中高级学习者挑战。',
    ),
  ];

  /// Bundled neural-TTS sample (scripts/gen_sample_audio.py), word-aligned
  /// with assets/data/sample_transcript.json. Playable fully offline.
  static const sampleAudio = 'asset://assets/audio/sample.mp3';
  static const sampleDuration = Duration(
      milliseconds: 17640);

  static List<Episode> episodesOf(String podcastId) => [
        Episode(
          id: '$podcastId-e1',
          podcastId: podcastId,
          podcastTitle:
              podcasts.firstWhere((p) => p.id == podcastId).title,
          title: '把喜欢的声音练进嘴里（示例单集）',
          audioUrl: sampleAudio,
          isLocal: true,
          localPath: sampleAudio,
          duration: sampleDuration,
          pubDate: DateTime(2026, 9, 20),
          language: 'en',
        ),
        Episode(
          id: '$podcastId-e2',
          podcastId: podcastId,
          podcastTitle:
              podcasts.firstWhere((p) => p.id == podcastId).title,
          title: '通勤路上的十分钟跟读训练（示例音频）',
          audioUrl: sampleAudio,
          isLocal: true,
          localPath: sampleAudio,
          duration: sampleDuration,
          pubDate: DateTime(2026, 9, 13),
          language: 'en',
        ),
      ];
}

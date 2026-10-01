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
    Podcast(
      id: 'p5',
      title: 'Hablemos Español',
      author: 'Radio Casa',
      feedUrl: 'https://example.com/feeds/hablemos-espanol.xml',
      language: 'es',
      level: ContentLevel.beginner,
      description: '生活化的西语对话，从点餐到旅行一路开口说。',
    ),
    Podcast(
      id: 'p6',
      title: '서울 스토리',
      author: '한국어 스튜디오',
      feedUrl: 'https://example.com/feeds/seoul-story.xml',
      language: 'ko',
      level: ContentLevel.intermediate,
      description: '首尔日常场景韩语播客，练听力也练敬语语感。',
    ),
    Podcast(
      id: 'p7',
      title: '中文慢谈',
      author: '慢声工作室',
      feedUrl: 'https://example.com/feeds/chinese-slow-talk.xml',
      language: 'zh',
      level: ContentLevel.intermediate,
      description: '用清晰普通话聊文化与生活，适合中文进阶学习者。',
    ),
    Podcast(
      id: 'p8',
      title: 'Everyday English News',
      author: 'Global Talk',
      feedUrl: 'https://example.com/feeds/everyday-english-news.xml',
      language: 'en',
      level: ContentLevel.advanced,
      description: '常速英语新闻短评，词汇密度高，适合高级学习者。',
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

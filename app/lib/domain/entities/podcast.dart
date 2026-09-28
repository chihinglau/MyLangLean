/// A discoverable podcast (RSS feed).
class Podcast {
  const Podcast({
    required this.id,
    required this.title,
    required this.feedUrl,
    this.author = '',
    this.artworkUrl,
    this.language = 'en',
    this.level = ContentLevel.all,
    this.description = '',
  });

  final String id;
  final String title;
  final String author;
  final String? artworkUrl;
  final String feedUrl;
  final String language;
  final ContentLevel level;
  final String description;

  factory Podcast.fromJson(Map<String, dynamic> json) => Podcast(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        feedUrl: json['feedUrl'] as String? ?? '',
        language: json['language'] as String? ?? 'en',
        level: ContentLevel.fromName(json['level'] as String?),
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'artworkUrl': artworkUrl,
        'feedUrl': feedUrl,
        'language': language,
        'level': level.name,
        'description': description,
      };
}

enum ContentLevel {
  beginner,
  intermediate,
  advanced,
  all;

  static ContentLevel fromName(String? name) =>
      ContentLevel.values.firstWhere((e) => e.name == name,
          orElse: () => ContentLevel.all);

  String get label => switch (this) {
        ContentLevel.beginner => '初级',
        ContentLevel.intermediate => '中级',
        ContentLevel.advanced => '高级',
        ContentLevel.all => '全部',
      };
}

/// Persisted learning preferences, edited on the profile page and consumed
/// by the player controller as playback defaults.
enum SubtitlePref {
  sourceOnly,
  bilingual,
  hidden;

  String get label => switch (this) {
        SubtitlePref.sourceOnly => '仅原文',
        SubtitlePref.bilingual => '双语对照',
        SubtitlePref.hidden => '盲听',
      };
}

class UserPreferences {
  const UserPreferences({
    this.defaultRate = 1.0,
    this.defaultFontScale = 1.0,
    this.subtitle = SubtitlePref.bilingual,
  });

  /// Default playback rate (one of Env.playRates).
  final double defaultRate;

  /// Default subtitle font scale (one of Env.fontScales).
  final double defaultFontScale;

  /// Default subtitle display mode.
  final SubtitlePref subtitle;

  UserPreferences copyWith({
    double? defaultRate,
    double? defaultFontScale,
    SubtitlePref? subtitle,
  }) =>
      UserPreferences(
        defaultRate: defaultRate ?? this.defaultRate,
        defaultFontScale: defaultFontScale ?? this.defaultFontScale,
        subtitle: subtitle ?? this.subtitle,
      );

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        defaultRate:
            (json['defaultRate'] as num?)?.toDouble() ?? 1.0,
        defaultFontScale:
            (json['defaultFontScale'] as num?)?.toDouble() ?? 1.0,
        subtitle: SubtitlePref.values.firstWhere(
          (e) => e.name == json['subtitle'],
          orElse: () => SubtitlePref.bilingual,
        ),
      );

  Map<String, dynamic> toJson() => {
        'defaultRate': defaultRate,
        'defaultFontScale': defaultFontScale,
        'subtitle': subtitle.name,
      };
}

/// Global constants. API base url can be injected at build time:
/// flutter build hap --dart-define=API_BASE_URL=https://api.example.com
class Env {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const String appName = 'MyLangLean';
  static const String appNameEn = 'MyLangLean';

  /// Guest free-preview window for transcripts (seconds), same rule as OORA.
  static const int guestPreviewSec = 300;

  /// Free monthly transcription quota after login (seconds = 100 minutes).
  static const int monthlyQuotaSec = 6000;

  /// Supported playback rates for shadowing.
  static const List<double> playRates = [0.6, 0.75, 0.85, 1.0, 1.25, 1.5];

  /// Subtitle font scale choices.
  static const List<double> fontScales = [0.85, 1.0, 1.15, 1.3, 1.5];
}

/// Screen-width break points (dp) for responsive layout.
class Breakpoints {
  static const double phone = 600;
  static const double tablet = 840;
}

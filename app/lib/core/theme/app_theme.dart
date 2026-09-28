import 'package:flutter/material.dart';

/// Dark-first Material 3 theme tuned for commuting / night study scenarios.
class AppTheme {
  static const Color _seed = Color(0xFF6C8CFF);
  static const Color _accent = Color(0xFFFFB15C);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ).copyWith(secondary: _accent),
        scaffoldBackgroundColor: const Color(0xFF0F1116),
        // cardColor works across Flutter 3.22 (OH fork) and 3.47 (official).
        // ignore: deprecated_member_use
        cardColor: const Color(0xFF181B22),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ).copyWith(secondary: _accent),
      );
}

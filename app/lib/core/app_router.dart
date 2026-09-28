import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/profile_page.dart';
import '../features/discover/discover_page.dart';
import '../features/history/history_page.dart';
import '../features/library/library_page.dart';
import '../features/player/player_page.dart';
import '../features/shadowing/shadowing_page.dart';
import 'home_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/discover',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final index = switch (state.matchedLocation) {
          '/library' => 1,
          '/history' => 2,
          '/profile' => 3,
          _ => 0,
        };
        return HomeShell(index: index, child: child);
      },
      routes: [
        GoRoute(path: '/discover', builder: (_, __) => const DiscoverPage()),
        GoRoute(path: '/library', builder: (_, __) => const LibraryPage()),
        GoRoute(path: '/history', builder: (_, __) => const HistoryPage()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
      ],
    ),
    GoRoute(
      path: '/player',
      pageBuilder: (_, __) =>
          const MaterialPage(child: PlayerPage(), fullscreenDialog: true),
    ),
    GoRoute(
      path: '/shadowing',
      pageBuilder: (_, __) =>
          const MaterialPage(child: ShadowingPage(), fullscreenDialog: true),
    ),
  ],
  errorBuilder: (context, state) =>
      Scaffold(body: Center(child: Text('页面不存在：${state.error}'))),
);

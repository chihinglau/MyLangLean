import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../data/repositories/synced_auth_repository.dart';
import '../domain/entities/quota.dart';
import '../features/player/player_controller.dart';
import '../features/update/update_flow.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.child, required this.index});

  final Widget child;
  final int index;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = ['/discover', '/library', '/history', '/profile'];

  static const _lastCheckKey = 'update.last_check_at';
  static const _checkInterval = Duration(hours: 24);

  StreamSubscription<String>? _noticeSub;
  StreamSubscription<Account>? _accountSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindAuthEvents();
      _autoCheckUpdate();
    });
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    _accountSub?.cancel();
    super.dispose();
  }

  /// Wires account/account-notice streams and also resolves the startup
  /// session future (the session check starts before the first frame, so a
  /// broadcast event alone could be missed).
  void _bindAuthEvents() {
    final auth = ref.read(authRepositoryProvider);
    if (auth is! SyncedAuthRepository) return;

    _noticeSub = auth.notices.listen(_showAccountNotice);
    _accountSub = auth.accountChanges.listen((_) {
      if (mounted) ref.read(accountRefreshProvider.notifier).state++;
    });

    // Fires even when the session resolved before this listener existed.
    auth.sessionReady?.then((_) {
      if (!mounted) return;
      ref.read(accountRefreshProvider.notifier).state++;
      _showPendingAccountNotice();
    });
  }

  void _showAccountNotice(String notice) {
    if (!mounted || notice.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(notice), duration: const Duration(seconds: 5)),
    );
  }

  /// Shows a one-shot notice persisted by the auth layer (e.g. account
  /// disabled) that was produced before the stream listener existed.
  Future<void> _showPendingAccountNotice() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth is! SyncedAuthRepository) return;
    final notice = await auth.consumeNotice();
    if (notice != null && notice.isNotEmpty) _showAccountNotice(notice);
  }

  /// Silent startup OTA check, throttled to once per 24h (mandatory releases
  /// bypass the throttle) and only attempted when the app has a persistence
  /// layer (real device build). Failures stay silent.
  Future<void> _autoCheckUpdate() async {
    final kv = ref.read(kvStoreProvider);
    if (kv == null) return;
    final info = await fetchUpdateQuietly(ref.read(mlApiProvider));
    if (!mounted || info == null) return;

    final lastMs = (kv.get(_lastCheckKey) as num?)?.toInt() ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    if (!info.mandatory &&
        DateTime.now().difference(last) < _checkInterval) {
      return;
    }
    await kv.set(
        _lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    await showUpdateFlow(context, info);
  }

  void _onTap(int i) => context.go(_tabs[i]);

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: widget.child),
          if (player.hasMedia)
            _MiniPlayer(
              title: player.episode!.title,
              isPlaying: player.isPlaying,
              position: controller.position,
              onTap: () => context.push('/player'),
              onToggle: controller.togglePlay,
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.index,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: '发现'),
          NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library),
              label: '资料库'),
          NavigationDestination(
              icon: Icon(Icons.timeline_outlined),
              selectedIcon: Icon(Icons.timeline),
              label: '履历'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.title,
    required this.isPlaying,
    required this.position,
    required this.onTap,
    required this.onToggle,
  });

  final String title;
  final bool isPlaying;
  final ValueNotifier<Duration> position;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    onPressed: onToggle,
                  ),
                  const Icon(Icons.keyboard_arrow_up, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

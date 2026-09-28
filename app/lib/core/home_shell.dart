import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/player/player_controller.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.child, required this.index});

  final Widget child;
  final int index;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = ['/discover', '/library', '/history', '/profile'];

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

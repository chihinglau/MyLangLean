import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';
import '../player/player_controller.dart';

class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(discoverResultsProvider);
    final filter = ref.watch(discoverFilterProvider);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('发现内容'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(108),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: '搜索播客、语言或主题（RSS）',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onSubmitted: (q) => ref
                        .read(discoverFilterProvider.notifier)
                        .state = filter.copyWith(query: q),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ContentLevel.values
                          .map((lvl) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(lvl.label),
                                  selected: filter.level == lvl,
                                  onSelected: (_) => ref
                                      .read(discoverFilterProvider
                                          .notifier)
                                      .state = filter.copyWith(
                                    level: lvl,
                                    clearLevel:
                                        lvl == ContentLevel.all,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        results.when(
          loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) =>
              SliverFillRemaining(child: Center(child: Text('加载失败：$e'))),
          data: (podcasts) => SliverList.builder(
            itemCount: podcasts.length,
            itemBuilder: (context, i) => _PodcastCard(
              podcast: podcasts[i],
              onPlay: () => _showEpisodes(context, ref, podcasts[i]),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }

  Future<void> _showEpisodes(
      BuildContext context, WidgetRef ref, Podcast podcast) async {
    final episodes =
        await ref.read(catalogRepositoryProvider).episodesOf(podcast);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => _EpisodeSheet(
          podcast: podcast,
          episodes: episodes,
          controller: controller,
        ),
      ),
    );
  }
}

class _PodcastCard extends StatelessWidget {
  const _PodcastCard({required this.podcast, required this.onPlay});

  final Podcast podcast;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor:
              Theme.of(context).colorScheme.primary.withOpacity(0.2),
          child: Text(podcast.language.toUpperCase(),
              style: const TextStyle(fontSize: 12)),
        ),
        title: Text(podcast.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(podcast.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                _Tag(podcast.level.label),
                const SizedBox(width: 6),
                _Tag(podcast.language),
              ],
            ),
          ],
        ),
        trailing: IconButton.filledTonal(
          onPressed: onPlay,
          icon: const Icon(Icons.playlist_play),
        ),
        onTap: onPlay,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _EpisodeSheet extends ConsumerWidget {
  const _EpisodeSheet({
    required this.podcast,
    required this.episodes,
    required this.controller,
  });

  final Podcast podcast;
  final List<Episode> episodes;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(podcast.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: '订阅',
                icon: const Icon(Icons.add),
                onPressed: () => ref
                    .read(libraryRepositoryProvider)
                    .toggleSubscription(podcast),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemCount: episodes.length,
            itemBuilder: (context, i) {
              final ep = episodes[i];
              return ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(ep.title),
                subtitle: Text(
                    '${ep.pubDate?.toString().split(' ').first ?? ''} · '
                    '${ep.duration.inMinutes} 分钟'),
                onTap: () async {
                  Navigator.pop(context);
                  await ref
                      .read(playerControllerProvider.notifier)
                      .playEpisode(ep);
                  if (context.mounted) context.push('/player');
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

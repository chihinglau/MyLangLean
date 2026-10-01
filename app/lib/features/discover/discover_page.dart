import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../domain/entities/podcast.dart';
import '../player/player_controller.dart';

/// Episode length label: short clips round up to "不足 1 分钟" instead of
/// showing a confusing "0 分钟".
String _formatDuration(Duration d) =>
    d.inMinutes < 1 ? '不足 1 分钟' : '${d.inMinutes} 分钟';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(discoverFilterProvider.notifier).state =
          ref.read(discoverFilterProvider).copyWith(query: value);
      if (value.trim().isNotEmpty) {
        ref.read(recentSearchesProvider.notifier).add(value.trim());
      }
    });
  }

  void _clearQuery() {
    _searchCtrl.clear();
    ref.read(discoverFilterProvider.notifier).state =
        ref.read(discoverFilterProvider).copyWith(query: '');
  }

  void _applyFilter(DiscoverFilter filter) =>
      ref.read(discoverFilterProvider.notifier).state = filter;

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(discoverResultsProvider);
    final filter = ref.watch(discoverFilterProvider);
    final recent = ref.watch(recentSearchesProvider);
    ref.watch(libraryRefreshProvider);
    final subscribed = ref
        .read(libraryRepositoryProvider)
        .subscriptions()
        .map((p) => p.id)
        .toSet();

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(discoverResultsProvider.future),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('发现内容'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(140),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜索播客、主题或语言',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchCtrl,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: _clearQuery,
                                ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onChanged: _onQueryChanged,
                      onSubmitted: (q) {
                        _applyFilter(filter.copyWith(query: q));
                        if (q.trim().isNotEmpty) {
                          ref
                              .read(recentSearchesProvider.notifier)
                              .add(q.trim());
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 30,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _chip(
                            label: ContentLevel.all.label,
                            selected: filter.level == null,
                            onTap: () => _applyFilter(
                                filter.copyWith(clearLevel: true)),
                          ),
                          for (final lvl in ContentLevel.values
                              .where((l) => l != ContentLevel.all))
                            _chip(
                              label: lvl.label,
                              selected: filter.level == lvl,
                              onTap: () =>
                                  _applyFilter(filter.copyWith(level: lvl)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 30,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _chip(
                            label: '全部语言',
                            selected: filter.language == null,
                            onTap: () => _applyFilter(
                                filter.copyWith(clearLanguage: true)),
                          ),
                          for (final entry in discoverLanguages.entries)
                            _chip(
                              label: entry.value,
                              selected: filter.language == entry.key,
                              onTap: () => _applyFilter(
                                  filter.copyWith(language: entry.key)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (filter.query.isEmpty && recent.isNotEmpty)
            SliverToBoxAdapter(
              child: _RecentSearches(
                recent: recent,
                onPick: (q) {
                  _searchCtrl.text = q;
                  _applyFilter(filter.copyWith(query: q));
                },
                onClear: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
              ),
            ),
          results.when(
            loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 44, color: Colors.white24),
                    const SizedBox(height: 10),
                    Text('加载失败：$e',
                        style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.invalidate(discoverResultsProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
            data: (podcasts) => podcasts.isEmpty
                ? SliverFillRemaining(child: _NoResults(onReset: _clearQuery))
                : SliverList.builder(
                    itemCount: podcasts.length,
                    itemBuilder: (context, i) => _PodcastCard(
                      podcast: podcasts[i],
                      subscribed: subscribed.contains(podcasts[i].id),
                      onOpen: () => _showEpisodes(context, podcasts[i]),
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );

  Future<void> _showEpisodes(BuildContext context, Podcast podcast) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Cover the shell's mini player / navigation bar as well.
      useRootNavigator: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => _EpisodeSheet(
          podcast: podcast,
          controller: controller,
        ),
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.recent,
    required this.onPick,
    required this.onClear,
  });

  final List<String> recent;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('最近搜索',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: onClear,
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final q in recent.take(6))
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.history, size: 14),
                  label: Text(q),
                  onPressed: () => onPick(q),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('没有找到符合条件的播客',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          TextButton(onPressed: onReset, child: const Text('清除搜索条件')),
        ],
      ),
    );
  }
}

class _PodcastCard extends StatelessWidget {
  const _PodcastCard({
    required this.podcast,
    required this.subscribed,
    required this.onOpen,
  });

  final Podcast podcast;
  final bool subscribed;
  final VoidCallback onOpen;

  static const _palette = [
    [Color(0xFF2E7D5B), Color(0xFF1B5E47)],
    [Color(0xFF355C9E), Color(0xFF243B6B)],
    [Color(0xFF8A5326), Color(0xFF5E3818)],
    [Color(0xFF94386A), Color(0xFF5E2345)],
    [Color(0xFF4A6B2E), Color(0xFF2F471D)],
  ];

  List<Color> get _colors =>
      _palette[podcast.id.codeUnits.fold(0, (s, c) => s + c) % _palette.length];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _colors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(podcast.language.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(podcast.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(podcast.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 4),
                    Text(podcast.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white38, height: 1.3)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Tag(podcast.level.label),
                        const SizedBox(width: 6),
                        _Tag(discoverLanguages[podcast.language] ??
                            podcast.language),
                        if (subscribed) ...[
                          const SizedBox(width: 6),
                          const _Tag('已订阅', highlight: true),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                onPressed: onOpen,
                icon: const Icon(Icons.playlist_play),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.highlight = false});
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? Theme.of(context).colorScheme.primary.withOpacity(0.22)
            : Colors.white12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: highlight
                  ? Theme.of(context).colorScheme.primary
                  : null)),
    );
  }
}

class _EpisodeSheet extends ConsumerWidget {
  const _EpisodeSheet({
    required this.podcast,
    required this.controller,
  });

  final Podcast podcast;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(podcastEpisodesProvider(podcast));
    ref.watch(libraryRefreshProvider);
    final subscribed = ref
        .read(libraryRepositoryProvider)
        .subscriptions()
        .any((p) => p.id == podcast.id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(podcast.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(podcast.author,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: Icon(subscribed ? Icons.check : Icons.add),
                label: Text(subscribed ? '已订阅' : '订阅'),
                onPressed: () async {
                  await ref
                      .read(libraryRepositoryProvider)
                      .toggleSubscription(podcast);
                  ref.read(libraryRefreshProvider.notifier).state++;
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(subscribed ? '已取消订阅' : '已订阅，可在资料库查看'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: episodesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('单集加载失败：$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54)),
              ),
            ),
            data: (episodes) => episodes.isEmpty
                ? const Center(
                    child: Text('这个播客暂时没有可播放的单集',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    controller: controller,
                    itemCount: episodes.length,
                    itemBuilder: (context, i) {
                      final ep = episodes[i];
                      return ListTile(
                        leading: const Icon(Icons.play_circle_outline),
                        title: Text(ep.title),
                        subtitle: Text(
                            '${ep.pubDate?.toString().split(' ').first ?? ''} · '
                            '${_formatDuration(ep.duration)}'),
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
        ),
      ],
    );
  }
}

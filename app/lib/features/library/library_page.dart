import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/synced_library_repository.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';
import '../../pal/pal_providers.dart';
import '../player/player_controller.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryRefreshProvider);
    final library = ref.read(libraryRepositoryProvider);
    final subscriptions = library.subscriptions();
    final localMedia = library.localMedia();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的内容'),
          bottom: const TabBar(tabs: [
            Tab(text: '本地音视频'),
            Tab(text: '播客订阅'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _importLocal(context, ref),
          icon: const Icon(Icons.file_open),
          label: const Text('导入音视频'),
        ),
        body: TabBarView(
          children: [
            if (localMedia.isEmpty)
              const _EmptyHint(icon: Icons.audio_file_outlined,
                  text: '还没有本地内容\n点击下方按钮导入音视频\n并可用「字幕工坊」的 JSON 配对字幕')
            else
              _EpisodeList(episodes: localMedia),
            _SubscriptionTab(subscriptions: subscriptions),
          ],
        ),
      ),
    );
  }

  Future<void> _importLocal(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ref.read(mediaPickerServiceProvider);

    final media = await picker.pickAudio();
    if (media == null) return;

    String? transcriptPath;
    if (!context.mounted) return;
    final wantSubtitle = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否配对字幕？'),
        content: const Text('选择电脑端「字幕工坊」导出的字幕 JSON 文件。\n'
            '没有字幕也可以先导入，稍后在条目菜单里关联。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('暂不')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('选择字幕')),
        ],
      ),
    );

    int? durationMs;
    String? language;
    if (wantSubtitle == true) {
      try {
        final pickedJson = await picker.pickFile(exts: const ['json']);
        if (pickedJson != null) {
          final parsed =
              jsonDecode(await File(pickedJson.path).readAsString())
                  as Map<String, dynamic>;
          final segments = parsed['segments'] as List<dynamic>?;
          if (segments == null || segments.isEmpty) {
            throw const FormatException('segments 为空');
          }
          transcriptPath = pickedJson.path;
          durationMs = ((parsed['duration'] as num?)?.toDouble() ?? 0) > 0
              ? ((parsed['duration'] as num).toDouble() * 1000).round()
              : null;
          language = parsed['language'] as String?;
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('字幕文件无效，已取消配对：$e')),
        );
        transcriptPath = null;
      }
    }

    final episode =
        await ref.read(libraryRepositoryProvider).addLocalMedia(
              media.path,
              transcriptPath: transcriptPath,
              title: media.title,
              language: language,
              durationMs: durationMs,
            );
    ref.read(libraryRefreshProvider.notifier).state++;
    if (!context.mounted) return;
    await ref.read(playerControllerProvider.notifier).playEpisode(episode);
    if (context.mounted) context.push('/player');
  }
}

class _SubscriptionTab extends ConsumerWidget {
  const _SubscriptionTab({required this.subscriptions});

  final List<Podcast> subscriptions;

  Future<void> _sync(WidgetRef ref) async {
    final library = ref.read(libraryRepositoryProvider);
    if (library is SyncedLibraryRepository) {
      await library.syncSubscriptions();
    }
    ref.read(libraryRefreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.read(libraryRepositoryProvider);
    return RefreshIndicator(
      onRefresh: () => _sync(ref),
      child: subscriptions.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(top: 96),
              children: const [
                _EmptyHint(
                    icon: Icons.radio_rounded,
                    text: '还没有订阅播客\n去「发现」找到喜欢的声音'),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: subscriptions.length,
              itemBuilder: (context, i) => ListTile(
                leading: const Icon(Icons.radio_rounded),
                title: Text(subscriptions[i].title),
                subtitle: Text(subscriptions[i].author),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await library.toggleSubscription(subscriptions[i]);
                    ref.read(libraryRefreshProvider.notifier).state++;
                  },
                ),
              ),
            ),
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({required this.episodes});
  final List<Episode> episodes;

  bool _isVideo(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    const videoExts = {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', 'ts'};
    return videoExts.contains(path.substring(dot + 1).toLowerCase());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: episodes.length,
      itemBuilder: (context, i) {
        final ep = episodes[i];
        return ListTile(
          leading: Icon(_isVideo(ep.localPath ?? ep.audioUrl)
              ? Icons.video_file
              : Icons.audio_file),
          title: Text(ep.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              Text(_isVideo(ep.localPath ?? ep.audioUrl) ? '视频音轨' : '本地文件'),
              const SizedBox(width: 8),
              Icon(
                ep.hasTranscriptFile ? Icons.closed_caption : Icons.subtitles_off,
                size: 14,
                color: ep.hasTranscriptFile
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white24,
              ),
              const SizedBox(width: 4),
              Text(ep.hasTranscriptFile ? '已配对字幕' : '无字幕',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, ref, v, ep),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'subtitle',
                child: Text(ep.hasTranscriptFile ? '替换字幕' : '关联字幕'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
          onTap: () async {
            await ref
                .read(playerControllerProvider.notifier)
                .playEpisode(ep);
            if (context.mounted) context.push('/player');
          },
        );
      },
    );
  }

  Future<void> _onMenu(
      BuildContext context, WidgetRef ref, String value, Episode ep) async {
    final messenger = ScaffoldMessenger.of(context);
    if (value == 'subtitle') {
      try {
        final picked = await ref
            .read(mediaPickerServiceProvider)
            .pickFile(exts: const ['json']);
        if (picked == null) return;
        // Validate before pairing.
        final parsed = jsonDecode(await File(picked.path).readAsString())
            as Map<String, dynamic>;
        if ((parsed['segments'] as List<dynamic>?)?.isEmpty ?? true) {
          throw const FormatException('segments 为空');
        }
        await ref
            .read(libraryRepositoryProvider)
            .attachTranscript(ep.id, picked.path);
        ref.read(libraryRefreshProvider.notifier).state++;
        messenger.showSnackBar(
          const SnackBar(content: Text('字幕已关联')),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('字幕文件无效：$e')));
      }
    } else if (value == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除这条内容？'),
          content: const Text('导入的媒体与配对字幕文件会一并删除。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) {
        await ref.read(libraryRepositoryProvider).removeLocalMedia(ep.id);
        ref.read(libraryRefreshProvider.notifier).state++;
      }
    }
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white24),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

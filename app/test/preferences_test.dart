import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mylanglean/data/kv_store.dart';
import 'package:mylanglean/data/providers.dart';
import 'package:mylanglean/domain/entities/user_preferences.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mll-prefs-test-');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ProviderContainer containerWith(KvStore kv) => ProviderContainer(overrides: [
        preferencesProvider.overrideWith((ref) => PreferencesNotifier(kv)),
        recentSearchesProvider
            .overrideWith((ref) => RecentSearchesNotifier(kv)),
      ]);

  test('preferences have sensible defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final prefs = container.read(preferencesProvider);
    expect(prefs.defaultRate, 1.0);
    expect(prefs.defaultFontScale, 1.0);
    expect(prefs.subtitle, SubtitlePref.bilingual);
  });

  test('preference edits persist across sessions', () async {
    final kv = await KvStore.open(dir);
    final container = containerWith(kv);
    addTearDown(container.dispose);

    await container
        .read(preferencesProvider.notifier)
        .setSubtitle(SubtitlePref.hidden);
    await container
        .read(preferencesProvider.notifier)
        .setDefaultRate(0.75);
    await container
        .read(preferencesProvider.notifier)
        .setDefaultFontScale(1.3);

    final reopenedKv = await KvStore.open(dir);
    final next = containerWith(reopenedKv);
    addTearDown(next.dispose);
    final restored = next.read(preferencesProvider);
    expect(restored.subtitle, SubtitlePref.hidden);
    expect(restored.defaultRate, 0.75);
    expect(restored.defaultFontScale, 1.3);
  });

  test('recent searches dedupe, newest-first and cap at ten', () async {
    final kv = await KvStore.open(dir);
    final container = containerWith(kv);
    addTearDown(container.dispose);
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.add('english');
    await notifier.add('french');
    await notifier.add('english'); // moves back to top, no duplicate
    expect(container.read(recentSearchesProvider), ['english', 'french']);

    for (var i = 0; i < 12; i++) {
      await notifier.add('q$i');
    }
    final list = container.read(recentSearchesProvider);
    expect(list.length, 10);
    expect(list.first, 'q11');

    await notifier.clear();
    expect(container.read(recentSearchesProvider), isEmpty);
  });

  test('blank queries are ignored by recent searches', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(recentSearchesProvider.notifier).add('   ');
    expect(container.read(recentSearchesProvider), isEmpty);
  });
}

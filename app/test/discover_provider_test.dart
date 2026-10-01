import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/providers.dart';
import 'package:mylanglean/domain/entities/podcast.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    // Keep the autoDispose provider alive between arrange/assert reads.
    container.listen(discoverResultsProvider, (_, __) {});
  });
  tearDown(() => container.dispose());

  Future<List<Podcast>> results() async {
    await container.read(discoverResultsProvider.future);
    return container.read(discoverResultsProvider).requireValue;
  }

  void setFilter(DiscoverFilter f) =>
      container.read(discoverFilterProvider.notifier).state = f;

  test('featured catalog lists all eight mock podcasts', () async {
    expect(await results(), hasLength(8));
  });

  test('level chip narrows results', () async {
    setFilter(const DiscoverFilter(level: ContentLevel.beginner));
    final list = await results();
    expect(list.map((p) => p.id), containsAll(['p1', 'p3', 'p5']));
    expect(list, everyElement((Podcast p) =>
        p.level == ContentLevel.beginner));
  });

  test('language chip narrows results', () async {
    setFilter(const DiscoverFilter(language: 'ja'));
    final list = await results();
    expect(list.map((p) => p.id), ['p2']);
  });

  test('combined level + language filters intersect', () async {
    setFilter(const DiscoverFilter(
      query: 'english',
      level: ContentLevel.advanced,
      language: 'en',
    ));
    final list = await results();
    expect(list.map((p) => p.id), ['p8']);
  });

  test('keyword search matches title', () async {
    setFilter(const DiscoverFilter(query: 'german'));
    final list = await results();
    expect(list.map((p) => p.id).toSet(), {'p4'});
  });

  test('clearing the query restores the featured list', () async {
    setFilter(const DiscoverFilter(query: 'totally-unknown-keyword'));
    expect(await results(), isEmpty);

    setFilter(const DiscoverFilter());
    expect(await results(), hasLength(8));
  });
}

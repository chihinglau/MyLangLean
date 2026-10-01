import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylanglean/data/kv_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mll-kv-');
  });

  tearDown(() async {
    if (dir.existsSync()) {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  });

  test('concurrent set/remove serialise without resurrecting removed keys',
      () async {
    final kv = await KvStore.open(dir);
    final futures = <Future<void>>[];
    for (var i = 0; i < 200; i++) {
      futures.add(kv.set('key$i', i));
      if (i.isEven) futures.add(kv.set('drop$i', i));
    }
    await Future.wait(futures);
    for (var i = 0; i < 200; i += 2) {
      await kv.remove('drop$i');
    }

    final reopened = await KvStore.open(dir);
    expect(reopened.get('key199'), 199);
    expect(reopened.get('key0'), 0);
    for (var i = 0; i < 200; i += 2) {
      expect(reopened.get('drop$i'), isNull,
          reason: 'removed key must not be resurrected by a stale write');
    }
  });

  test('remove followed immediately by set lands in persisted order',
      () async {
    final kv = await KvStore.open(dir);
    await kv.set('auth.token', 'user-jwt');
    // Hammer unrelated keys at the same time (boot-time fan-out writes).
    final noise = List.generate(
        40, (i) => kv.set('cache.$i', List.filled(64, 'x').join()));
    await Future.wait([
      ...noise,
      kv.remove('auth.token'),
      kv.set('auth.guest', true),
    ]);

    final reopened = await KvStore.open(dir);
    expect(reopened.getString('auth.token'), isNull);
    expect(reopened.getBool('auth.guest'), isTrue);

    // No leftover tmp files.
    final leftovers = dir.listSync().whereType<File>().where(
        (f) => f.uri.pathSegments.last.startsWith('prefs.json.tmp.'));
    expect(leftovers, isEmpty);
  });
}

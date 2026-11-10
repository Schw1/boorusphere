import 'dart:io';

import 'package:boorusphere/data/repository/server/server_pins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('pins').path);
  });

  test('pin, unpin, kept across opening', () async {
    await ServerPins.open();
    expect(ServerPins.pinned.value, isEmpty);
    await ServerPins.toggle('Danbooru');
    await ServerPins.toggle('Monbooru');
    await ServerPins.toggle('Danbooru');
    expect(ServerPins.pinned.value, {'Monbooru'});
    ServerPins.pinned.value = const {};
    await ServerPins.open();
    expect(ServerPins.isPinned('Monbooru'), isTrue);
  });

  test('backup round trip adds pins', () async {
    final exported = ServerPins.export();
    await ServerPins.import(['Gelbooru', 3, '', ...exported]);
    expect(ServerPins.pinned.value, containsAll(['Gelbooru', 'Monbooru']));
    expect(ServerPins.export(), ['Gelbooru', 'Monbooru']);
    await ServerPins.import('broken');
    expect(ServerPins.export(), hasLength(2));
  });
}

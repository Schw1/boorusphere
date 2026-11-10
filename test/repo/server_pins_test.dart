import 'dart:io';

import 'package:boorusphere/data/repository/server/server_pins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late ServerPins pins;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('pins').path);
    await ServerPins.openBox();
    pins = ServerPins.fromOpenBox();
  });

  test('pin, unpin, kept across opening', () async {
    expect(pins.pinned.value, isEmpty);
    await pins.toggle('Danbooru');
    await pins.toggle('Monbooru');
    await pins.toggle('Danbooru');
    expect(pins.pinned.value, {'Monbooru'});
    // a new store on the same box (the next app start)
    pins = ServerPins.fromOpenBox();
    expect(pins.isPinned('Monbooru'), isTrue);
  });

  test('backup round trip adds pins', () async {
    final exported = pins.export();
    await pins.import(['Gelbooru', 3, '', ...exported]);
    expect(pins.pinned.value, containsAll(['Gelbooru', 'Monbooru']));
    expect(pins.export(), ['Gelbooru', 'Monbooru']);
    await pins.import('broken');
    expect(pins.export(), hasLength(2));
  });
}

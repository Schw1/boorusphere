import 'dart:io';

import 'package:boorusphere/data/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory docs;
  late Directory hive;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_storage');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    hive = Directory(p.join(root.path, 'Support', 'hive'));
  });

  tearDown(() async {
    await Hive.close();
    root.deleteSync(recursive: true);
  });

  File doc(String name, [String content = 'x']) => File(p.join(docs.path, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  List<String> names(Directory dir) =>
      dir.listSync().map((it) => p.basename(it.path)).toList()..sort();

  test('boxes written in Documents are there after the move', () async {
    Hive.init(docs.path);
    final box = await Hive.openBox<String>('favorites');
    await box.put('a', 'one');
    await box.put('b', 'two');
    await Hive.close();

    final path = await AppStorage.moveHiveData(from: docs, to: hive);
    expect(path, hive.path);

    Hive.init(path);
    final moved = await Hive.openBox<String>('favorites');
    expect(moved.toMap(), {'a': 'one', 'b': 'two'});
    expect(docs.listSync().where((it) => it.path.endsWith('.hive')), isEmpty);
  });

  test('only Hive files move; downloads and backups stay', () async {
    doc('server.hive');
    doc('settings.hivec');
    doc('settings.lock');
    doc('Boorusphere/picture.jpg');
    doc('Boorusphere/backups/boorusphere_backup_1.zip');

    await AppStorage.moveHiveData(from: docs, to: hive);

    expect(names(hive), [AppStorage.marker, 'server.hive', 'settings.hivec']);
    expect(names(docs), ['Boorusphere']);
    expect(
      File(p.join(docs.path, 'Boorusphere', 'picture.jpg')).existsSync(),
      true,
    );
  });

  test('a fresh install starts in the new folder', () async {
    final path = await AppStorage.moveHiveData(from: docs, to: hive);
    expect(path, hive.path);
    expect(names(hive), [AppStorage.marker]);
  });

  test('a finished move is not repeated; leftovers are deleted', () async {
    doc('server.hive', 'old');
    await AppStorage.moveHiveData(from: docs, to: hive);
    File(p.join(hive.path, 'server.hive')).writeAsStringSync('new');
    // the old file came back, e.g. it could not be deleted last time
    doc('server.hive', 'old');

    final path = await AppStorage.moveHiveData(from: docs, to: hive);
    expect(path, hive.path);
    expect(File(p.join(hive.path, 'server.hive')).readAsStringSync(), 'new');
    expect(File(p.join(docs.path, 'server.hive')).existsSync(), false);
  });

  test('an interrupted move starts over from the originals', () async {
    doc('server.hive', 'complete');
    doc('favorites.hive', 'complete');
    // half copied, no marker
    File(p.join(hive.path, 'server.hive'))
      ..createSync(recursive: true)
      ..writeAsStringSync('half');

    await AppStorage.moveHiveData(from: docs, to: hive);
    expect(
      File(p.join(hive.path, 'server.hive')).readAsStringSync(),
      'complete',
    );
    expect(
      File(p.join(hive.path, 'favorites.hive')).readAsStringSync(),
      'complete',
    );
  });

  test('if copying fails, the data stays where it is and is used', () async {
    doc('server.hive', 'data');
    // the target can't be created: a file is in the way
    final blocker = File(p.join(root.path, 'Support'))..createSync();
    final target = Directory(p.join(blocker.path, 'hive'));

    final path = await AppStorage.moveHiveData(from: docs, to: target);
    expect(path, docs.path);
    expect(File(p.join(docs.path, 'server.hive')).readAsStringSync(), 'data');
  });

  test('the cookie folder moves with its contents', () async {
    doc('cookies/ie0_ps1/.index', 'index');
    doc('cookies/ie0_ps1/abc', 'cookie');
    final to = Directory(p.join(root.path, 'Support', 'cookies'));

    final path = await AppStorage.moveDirectory(
      from: Directory(p.join(docs.path, 'cookies')),
      to: to,
    );
    expect(path, to.path);
    expect(
      File(p.join(to.path, 'ie0_ps1', 'abc')).readAsStringSync(),
      'cookie',
    );
    expect(File(p.join(to.path, 'ie0_ps1', '.index')).existsSync(), true);
    expect(Directory(p.join(docs.path, 'cookies')).existsSync(), false);
  });
}

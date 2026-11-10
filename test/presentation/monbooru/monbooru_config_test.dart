import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The monloader settings are kept in memory between requests (a job is
/// polled every 2 s). Every way of changing them has to show up at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('monloader').path);
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('saved settings are loaded', () async {
    await MonbooruSender.save('192.168.1.5:8456/', ' token-a ');
    final config = await MonbooruSender.load();
    expect(config.url, 'http://192.168.1.5:8456');
    expect(config.token, 'token-a');
  });

  test('saving again replaces what was loaded before', () async {
    await MonbooruSender.save('http://one', 'token-a');
    expect((await MonbooruSender.load()).url, 'http://one');

    await MonbooruSender.save('http://two', 'token-b');
    final config = await MonbooruSender.load();
    expect(config.url, 'http://two');
    expect(config.token, 'token-b');
  });

  test('removing the token shows up', () async {
    await MonbooruSender.save('http://one', 'token-a');
    expect((await MonbooruSender.load()).isComplete, true);

    await MonbooruSender.save('http://one', '');
    expect((await MonbooruSender.load()).isComplete, false);
  });

  test('a restored backup replaces what was loaded before', () async {
    await MonbooruSender.save('http://one', 'token-a');
    expect((await MonbooruSender.load()).url, 'http://one');

    await MonbooruSender.importBackup(
      jsonEncode({'url': 'http://restored', 'token': 'token-r'}),
    );
    final config = await MonbooruSender.load();
    expect(config.url, 'http://restored');
    expect(config.token, 'token-r');
  });
}

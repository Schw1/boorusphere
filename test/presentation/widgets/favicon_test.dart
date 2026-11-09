import 'dart:io';
import 'dart:typed_data';

import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers `/favicon.ico` with a PNG and counts the requests.
class _IconServer implements HttpClientAdapter {
  int requests = 0;
  bool online = true;

  static final png = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    1,
    2,
    3,
    4,
  ]);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (!online || options.uri.path != '/favicon.ico') {
      return ResponseBody.fromBytes(const [], 404);
    }
    return ResponseBody.fromBytes(png, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late _IconServer server;
  final site = Uri.parse('http://192.168.1.5:8455/some/page');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('favicon_test');
    server = _IconServer();
    FaviconLoader.directory = dir;
    FaviconLoader.client = Dio()..httpClientAdapter = server;
    FaviconLoader.resetMemory();
  });

  tearDown(() {
    FaviconLoader.directory = null;
    FaviconLoader.client = null;
    FaviconLoader.resetMemory();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('an icon is stored and not requested again at the next start', () async {
    expect(await FaviconLoader.load('test', site), _IconServer.png);
    expect(server.requests, 1);
    expect(dir.listSync().whereType<File>().length, 1);

    // next app start: nothing in memory, the icon comes from disk
    FaviconLoader.resetMemory();
    expect(await FaviconLoader.load('test', site), _IconServer.png);
    expect(server.requests, 1);
  });

  test('an old icon is refreshed', () async {
    await FaviconLoader.load('test', site);
    final file = dir.listSync().whereType<File>().single;
    file.setLastModifiedSync(
      DateTime.now().subtract(FaviconLoader.maxAge + const Duration(hours: 1)),
    );

    FaviconLoader.resetMemory();
    expect(await FaviconLoader.load('test', site), _IconServer.png);
    expect(server.requests, 2);
  });

  test('an old icon is still used while the server is unreachable', () async {
    await FaviconLoader.load('test', site);
    final file = dir.listSync().whereType<File>().single;
    file.setLastModifiedSync(
      DateTime.now().subtract(FaviconLoader.maxAge + const Duration(hours: 1)),
    );

    FaviconLoader.resetMemory();
    server.online = false;
    expect(await FaviconLoader.load('test', site), _IconServer.png);
  });

  test('clear removes the stored icons', () async {
    await FaviconLoader.load('test', site);
    await FaviconLoader.clear();
    expect(dir.existsSync(), false);

    expect(await FaviconLoader.load('test', site), _IconServer.png);
    expect(server.requests, 2);
  });
}

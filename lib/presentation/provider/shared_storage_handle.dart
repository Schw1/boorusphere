import 'dart:io';

import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shared_storage_handle.g.dart';

@Riverpod(keepAlive: true)
SharedStorageHandle sharedStorageHandle(Ref ref) {
  throw UnimplementedError();
}

Future<SharedStorageHandle> provideSharedStorageHandle() async {
  if (Platform.isIOS) {
    // iOS has no public Downloads directory; use the app's Documents directory
    // (visible in the Files app when UIFileSharingEnabled is set).
    final docs = await getApplicationDocumentsDirectory();
    return SharedStorageHandle(downloadPath: docs.path);
  }
  final downloadPath = await StorageUtil().getDownloadPath();
  return SharedStorageHandle(downloadPath: downloadPath);
}

class SharedStorageHandle {
  SharedStorageHandle({required this.downloadPath});

  final String downloadPath;

  String get path {
    return p.join(downloadPath, 'Boorusphere');
  }

  File get _nomedia {
    return File(p.join(path, '.nomedia'));
  }

  bool get isHidden {
    return _nomedia.existsSync();
  }

  Future<void> init() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }
    final dir = Directory(path);
    if (!dir.existsSync()) {
      try {
        Directory(path).createSync();
        // ignore: empty_catches
      } catch (e) {}
    }
  }

  Directory createSubDir(String directory) {
    final dir = Directory(p.join(path, directory));
    try {
      dir.createSync();
      // ignore: empty_catches
    } catch (e) {}
    return dir;
  }

  bool fileExists(String relativePath) {
    final file = File(p.join(path, Uri.decodeFull(relativePath)));
    try {
      return file.existsSync();
      // ignore: empty_catches
    } catch (e) {}
    return false;
  }

  Future<void> rescan() async {
    // MediaScanner is Android-only
    if (!Platform.isAndroid) return;
    await MediaScanner.loadMedia(path: path);
  }

  Future<void> hide(bool hide) async {
    await init();
    final isExists = _nomedia.existsSync();
    try {
      if (hide && !isExists) {
        await _nomedia.create();
      } else if (!hide && isExists) {
        await _nomedia.delete();
      }
      // ignore: empty_catches
    } catch (e) {}
    await rescan();
  }

  Future<void> open(String dest, {String? on}) async {
    try {
      final filePath = p.join(on ?? path, Uri.decodeFull(dest));
      if (Platform.isIOS) {
        await OpenFilex.open(filePath);
      } else {
        await StorageUtil().open(filePath);
      }
      // ignore: empty_catches
    } catch (e) {}
  }
}

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'downloader.g.dart';

// keepAlive: the service keeps its Ref and uses it after awaits; with
// Riverpod 3 an auto-disposed Ref throws once the provider is gone.
@Riverpod(keepAlive: true)
Downloader downloader(Ref ref) {
  return Downloader(ref);
}

class Downloader {
  Downloader(this.ref);

  final Ref ref;

  Future<String?> download(
    Post post, {
    String? url,
    String Function(String fileName)? dest,
  }) async {
    final fileUrl = url ?? post.originalFile;
    // sanitize forbidden characters on the file name
    final fileName = Uri.decodeComponent(
      fileUrl.fileName,
    ).replaceAll(RegExp(r'([^a-zA-Z0-9\s\.\(\)_]+)'), '_');
    final sharedStorageHandle = ref.read(sharedStorageHandleProvider);

    await sharedStorageHandle.init();
    final versionRepo = ref.read(versionRepoProvider);
    final server = ref
        .read(serverStateProvider)
        .cast<Server?>()
        .firstWhere((it) => it?.id == post.serverId, orElse: () => null);
    final authHeaders = server == null
        ? const <String, String>{}
        : ServerAuthStore.headersFor(server, fileUrl);
    final taskId = await FlutterDownloader.enqueue(
      url: fileUrl,
      fileName: fileName,
      savedDir: sharedStorageHandle.path,
      showNotification: true,
      openFileFromNotification: true,
      headers:
          HeadersFactory.builder()
              .setUserAgent(versionRepo.current)
              .setReferer(createReferer(fileUrl))
              .build()
            ..addAll(authHeaders),
    );

    if (taskId != null) {
      final entry = DownloadEntry(
        id: taskId,
        post: post,
        dest: dest?.call(fileName) ?? fileName,
      );
      await ref.read(downloadEntryStateProvider.notifier).add(entry);
    }
    return taskId;
  }

  Future<void> retry({required String id}) async {
    final newId = await FlutterDownloader.retry(taskId: id);
    if (newId != null) {
      final newEntry = ref
          .read(downloadEntryStateProvider)
          .firstWhere((it) => it.id == id, orElse: DownloadEntry.new)
          .copyWith(id: newId);

      await ref.read(downloadEntryStateProvider.notifier).update(id, newEntry);
    }
  }

  Future<void> cancel({required String id}) async {
    await FlutterDownloader.cancel(taskId: id);
  }

  Future<void> clear({required String id}) async {
    await FlutterDownloader.remove(taskId: id, shouldDeleteContent: false);
    await ref.read(downloadEntryStateProvider.notifier).remove(id);
  }

  void openFile({required String id}) {
    final entry = ref.read(downloadEntryStateProvider).getById(id);
    ref.read(sharedStorageHandleProvider).open(entry.dest);
  }
}

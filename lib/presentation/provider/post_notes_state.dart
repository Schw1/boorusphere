import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/post_notes.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether notes are drawn over images (toggle in the viewer, for this
/// app session).
final postNotesVisible = ValueNotifier(true);

/// Notes of [post]; empty when it has none or they can't be loaded.
final postNotesProvider =
    FutureProvider.autoDispose.family<List<PostNote>, Post>((ref, post) async {
  final server = ref.read(serverStateProvider).findById(post.serverId);
  if (server == null) return const [];
  final url = PostNotes.urlOf(server, post);
  if (url == null) return const [];
  try {
    final res = await ref.read(dioProvider).get(
          url,
          options: Options(
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'Boorusphere/${displayVersion('dev')}',
            },
            validateStatus: (it) => it == 200,
          ),
        );
    return PostNotes.parse(res.data);
  } catch (_) {
    return const [];
  }
});

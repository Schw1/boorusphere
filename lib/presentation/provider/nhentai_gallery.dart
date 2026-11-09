import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Galleries already loaded this session, by "<serverId>:<id>".
final _cache = <String, NhentaiGallery>{};

/// Pages, cover and tag names of an nhentai gallery post; null when the
/// post isn't from nhentai or the gallery can't be loaded.
final nhentaiGalleryProvider =
    FutureProvider.autoDispose.family<NhentaiGallery?, Post>((ref, post) async {
  final server = ref.read(serverStateProvider).findById(post.serverId);
  if (!NhentaiJsonParser.isNhentai(server)) return null;
  final key = '${post.serverId}:${post.id}';
  final cached = _cache[key];
  if (cached != null) return cached;

  final res = await ref.read(dioProvider).get(
        NhentaiGallery.galleryApiUrl(server!, post.id),
        options: Options(
          headers: {'Accept': 'application/json'},
          validateStatus: (it) => it == 200,
        ),
      );
  final gallery = NhentaiGallery.fromJson(res.data);
  if (gallery != null) _cache[key] = gallery;
  return gallery;
});

/// Galleries nhentai lists as related to [post]; empty when the post isn't
/// from nhentai or the list can't be loaded (it's only a bonus).
final nhentaiRelatedProvider =
    FutureProvider.autoDispose.family<List<Post>, Post>((ref, post) async {
  final server = ref.read(serverStateProvider).findById(post.serverId);
  if (!NhentaiJsonParser.isNhentai(server)) return const [];
  try {
    final res = await ref.read(dioProvider).get(
          NhentaiGallery.relatedApiUrl(server!, post.id),
          options: Options(
            headers: {'Accept': 'application/json'},
            validateStatus: (it) => it == 200,
          ),
        );
    return NhentaiJsonParser.parseRelated(server, res.data)
        .where((it) => it.id != post.id)
        .toList();
  } catch (_) {
    return const [];
  }
});

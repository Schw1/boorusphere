import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/nhentai_gallery.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/post/post_viewer.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// A row of galleries nhentai lists as related to [post]. Tapping one opens
/// it in the viewer, where the others can be swiped through. Nothing is
/// shown while loading or when there are none.
class RelatedGalleries extends HookConsumerWidget {
  const RelatedGalleries({super.key, required this.post, required this.session});

  final Post post;
  final SearchSession session;

  static const _height = 190.0;
  static const _width = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(nhentaiRelatedProvider(post)).value ?? const [];
    final scrollController = useMemoized(AutoScrollController.new);
    useEffect(() => scrollController.dispose, [scrollController]);
    if (related.isEmpty) return const SizedBox.shrink();

    // The viewer needs a timeline to follow; this one only scrolls the row.
    return ProviderScope(
      overrides: [
        searchSessionProvider.overrideWith((ref) => session),
        timelineControllerProvider.overrideWith(
            (ref) => TimelineController(scrollController: scrollController)),
      ],
      child: ListTile(
        title: Text(context.t.gallery.related),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            height: _height,
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => AutoScrollTag(
                key: ValueKey(index),
                controller: scrollController,
                index: index,
                child: _Item(
                  post: related[index],
                  width: _width,
                  onTap: () =>
                      PostViewer.open(context, index: index, posts: related),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends ConsumerWidget {
  const _Item({required this.post, required this.width, required this.onTap});

  final Post post;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final blur =
        ref.watch(contentSettingStateProvider.select((it) => it.blurExplicit));
    Widget image = ExtendedImage.network(
      post.previewFile,
      headers: headers,
      cache: true,
      fit: BoxFit.cover,
      width: width,
    );
    if (blur) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: image,
      );
    }

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: context.colorScheme.surfaceContainerHighest,
                      child: image,
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${post.pageCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

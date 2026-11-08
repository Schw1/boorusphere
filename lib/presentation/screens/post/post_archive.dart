import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/post/post_image.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An archive (Monbooru CBZ) in the post viewer: the cover, plus a button
/// that opens the reader.
class PostArchive extends StatelessWidget {
  const PostArchive({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        PostImage(post: post),
        Align(
          alignment: const Alignment(0, 0.62),
          child: FilledButton.icon(
            onPressed: () => ArchiveReaderPage.open(context, post),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(context.t.archive.read(n: post.pageCount)),
          ),
        ),
      ],
    );
  }
}

/// Reads an archive page by page, left to right, with pinch zoom.
class ArchiveReaderPage extends HookConsumerWidget {
  const ArchiveReaderPage({super.key, required this.post});

  final Post post;

  static Future<void> open(BuildContext context, Post post) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ArchiveReaderPage(post: post),
    ));
  }

  /// URLs of all pages. Page 1 is the cover the viewer already shows.
  static List<String> pageUrls(String api, Post post) {
    final hash = post.md5.isNotEmpty ? post.md5 : '${post.id}';
    return [
      for (var n = 1; n <= post.pageCount; n++)
        MonbooruJsonParser.pageUrl(api, post.id, n, hash),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverStateProvider).findById(post.serverId);
    // Same origin as the cover, so the same headers (incl. token) apply.
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final urls = useMemoized(
      () => server == null ? <String>[] : pageUrls(server.apiAddress, post),
      [server?.apiAddress, post.viewId],
    );
    final page = useState(0);
    final showBars = useState(true);
    final controller = useMemoized(ExtendedPageController.new);
    useEffect(() => controller.dispose, [controller]);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: showBars.value
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text(context.t.archive.page(
                  current: page.value + 1, total: urls.length)),
            )
          : null,
      body: urls.isEmpty
          ? Center(
              child: Text(context.t.loadImageFailed,
                  style: const TextStyle(color: Colors.white)),
            )
          : Stack(
              children: [
                GestureDetector(
                  onTap: () => showBars.value = !showBars.value,
                  child: ExtendedImageGesturePageView.builder(
                    controller: controller,
                    itemCount: urls.length,
                    onPageChanged: (i) => page.value = i,
                    itemBuilder: (context, index) => ExtendedImage.network(
                      urls[index],
                      headers: headers,
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.gesture,
                      cache: true,
                      initGestureConfigHandler: (_) => GestureConfig(
                        minScale: 1,
                        maxScale: 5,
                        inPageView: true,
                      ),
                      loadStateChanged: (state) => switch (
                          state.extendedImageLoadState) {
                        LoadState.loading => const Center(
                            child: CircularProgressIndicator(),
                          ),
                        LoadState.failed => Center(
                            child: TextButton.icon(
                              onPressed: state.reLoadImage,
                              icon: const Icon(Icons.refresh),
                              label: Text(context.t.retry),
                            ),
                          ),
                        LoadState.completed => null,
                      },
                    ),
                  ),
                ),
                if (showBars.value && urls.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _PageSlider(
                      page: page.value,
                      total: urls.length,
                      onChanged: (i) => controller.jumpToPage(i),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PageSlider extends StatelessWidget {
  const _PageSlider({
    required this.page,
    required this.total,
    required this.onChanged,
  });

  final int page;
  final int total;
  final void Function(int page) onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text('${page + 1}', style: const TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: (total - 1).toDouble(),
                  divisions: total - 1,
                  value: page.toDouble().clamp(0, (total - 1).toDouble()),
                  activeColor: context.colorScheme.primary,
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
              Text('$total', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

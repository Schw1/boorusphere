import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/nhentai_gallery.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/post/post_image.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An archive (Monbooru CBZ) or gallery (nhentai) in the post viewer: the
/// cover, plus a button that opens the reader.
class PostArchive extends HookConsumerWidget {
  const PostArchive({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverStateProvider).findById(post.serverId);
    final isGallery = NhentaiJsonParser.isNhentai(server);
    // nhentai lists only a small thumbnail; the gallery has the real cover.
    final gallery =
        isGallery ? ref.watch(nhentaiGalleryProvider(post)).value : null;
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final cover = gallery?.cover ?? '';
    // Last page read; rebuilt when the reader saves a page.
    useValueListenable(ReadingProgress.changes);
    final saved = useFuture(
      useMemoized(() => ReadingProgress.pageOf(post),
          [post.viewId, ReadingProgress.changes.value]),
    ).data;
    final finished = saved != null && saved >= post.pageCount - 1;
    final resume = saved != null && saved > 0 && !finished;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (cover.isEmpty)
          PostImage(post: post)
        else
          ExtendedImage.network(
            cover,
            headers: headers,
            fit: BoxFit.contain,
            cache: true,
            mode: ExtendedImageMode.gesture,
            initGestureConfigHandler: (_) =>
                GestureConfig(minScale: 1, maxScale: 3, inPageView: true),
          ),
        Align(
          alignment: const Alignment(0, 0.62),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (post.title.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    post.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              FilledButton.icon(
                onPressed: () => ArchiveReaderPage.open(context, post,
                    startPage: resume ? saved! : 0),
                icon: Icon(resume
                    ? Icons.auto_stories_outlined
                    : Icons.menu_book_outlined),
                label: Text(resume
                    ? context.t.archive
                        .resume(page: saved! + 1, n: post.pageCount)
                    : finished
                        ? context.t.archive.readAgain(n: post.pageCount)
                        : context.t.archive.read(n: post.pageCount)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reads an archive page by page, left to right, with pinch zoom.
class ArchiveReaderPage extends HookConsumerWidget {
  const ArchiveReaderPage({super.key, required this.post, this.startPage = 0});

  final Post post;

  /// 0-based page to open at (the last page read).
  final int startPage;

  static Future<void> open(BuildContext context, Post post,
      {int startPage = 0}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ArchiveReaderPage(post: post, startPage: startPage),
    ));
  }

  /// Pages loaded ahead of the current one.
  static const preloadPages = 3;

  /// Indexes to load in the background while [page] of [total] is shown:
  /// the next [preloadPages], then the previous one.
  static List<int> preloadRange(int page, int total) => [
        for (var i = page + 1; i <= page + preloadPages && i < total; i++) i,
        if (page - 1 >= 0 && page - 1 < total) page - 1,
      ];

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
    final isGallery = NhentaiJsonParser.isNhentai(server);
    // Same origin as the cover, so the same headers (incl. token) apply.
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final gallery = isGallery ? ref.watch(nhentaiGalleryProvider(post)) : null;
    final archiveUrls = useMemoized(
      () => server == null || isGallery
          ? <String>[]
          : pageUrls(server.apiAddress, post),
      [server?.apiAddress, post.viewId, isGallery],
    );
    // nhentai: the page list comes with the gallery.
    final urls = isGallery ? gallery?.value?.pages ?? const [] : archiveUrls;
    final loading = gallery?.isLoading ?? false;
    final page = useState(startPage);
    final showBars = useState(true);
    final controller =
        useMemoized(() => ExtendedPageController(initialPage: startPage));
    useEffect(() => controller.dispose, [controller]);
    // Remember the page (also the first one, so a started archive shows up
    // as such).
    useEffect(() {
      ReadingProgress.save(post, page.value);
      return null;
    }, [page.value]);
    // Load the next pages in the background, so turning the page doesn't
    // wait. Same provider settings as the page view, so the cache matches.
    useEffect(() {
      if (urls.isEmpty) return null;
      for (final i in preloadRange(page.value, urls.length)) {
        precacheImage(
          ExtendedNetworkImageProvider(urls[i], headers: headers, cache: true),
          context,
          onError: (_, __) {},
        );
      }
      return null;
    }, [page.value, urls.length]);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: showBars.value
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text(context.t.archive.page(
                  current: page.value + 1,
                  total: urls.isEmpty ? post.pageCount : urls.length)),
            )
          : null,
      body: urls.isEmpty
          ? Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : Text(context.t.loadImageFailed,
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

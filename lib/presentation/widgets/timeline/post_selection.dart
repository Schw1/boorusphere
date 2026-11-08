import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/monbooru_error.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/root_messenger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Posts picked in a timeline (long-press to start, tap to add/remove).
class PostSelection extends ChangeNotifier {
  final Map<String, Post> _selected = {};

  bool get isActive => _selected.isNotEmpty;
  int get length => _selected.length;
  List<Post> get posts => _selected.values.toList();
  bool contains(Post post) => _selected.containsKey(post.viewId);

  void toggle(Post post) {
    if (_selected.remove(post.viewId) == null) {
      _selected[post.viewId] = post;
    }
    notifyListeners();
  }

  void selectAll(Iterable<Post> posts) {
    for (final post in posts) {
      if (!post.isReserved) _selected[post.viewId] = post;
    }
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  static PostSelection? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PostSelectionInherited>()
      ?.notifier;
}

class _PostSelectionInherited extends InheritedNotifier<PostSelection> {
  const _PostSelectionInherited({
    required PostSelection selection,
    required super.child,
  }) : super(notifier: selection);
}

/// Enables selecting posts in the [Timeline]s below and shows the action bar
/// on top while posts are selected.
class PostSelectionScope extends HookWidget {
  const PostSelectionScope({
    super.key,
    required this.posts,
    required this.child,
  });

  /// All posts currently loaded, for "select all".
  final Iterable<Post> Function() posts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selection = useMemoized(PostSelection.new);
    useEffect(() => selection.dispose, [selection]);
    final active = useListenableSelector(selection, () => selection.isActive);

    return _PostSelectionInherited(
      selection: selection,
      child: PopScope(
        // Back leaves the selection first.
        canPop: !active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) selection.clear();
        },
        child: Stack(
          children: [
            child,
            if (active)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _SelectionBar(selection: selection, posts: posts),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends HookConsumerWidget {
  const _SelectionBar({required this.selection, required this.posts});

  final PostSelection selection;
  final Iterable<Post> Function() posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useListenable(selection);
    final progress = useState<(int, int)?>(null);
    final t = context.t.monbooru.selection;

    Future<void> send() async {
      final servers = ref.read(serverStateProvider);
      // Posts that come from Monbooru itself are not sent back to it.
      final picked = selection.posts.where((post) {
        final server = servers.findById(post.serverId);
        return server == null || !MonbooruJsonParser.isMonbooru(server);
      }).toList();
      progress.value = (0, picked.length);
      final report = await MonbooruQueue.instance.sendAll(
        picked,
        servers,
        onProgress: (sent, total) {
          if (context.mounted) progress.value = (sent, total);
        },
      );
      if (context.mounted) {
        progress.value = null;
        selection.clear();
      }
      showRootSnackBar((c) => report.describe(c),
          duration: const Duration(seconds: 6));
    }

    final sending = progress.value;
    return SafeArea(
      bottom: false,
      child: Card(
        margin: const EdgeInsets.all(8),
        elevation: 4,
        color: context.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: t.clear,
                icon: const Icon(Icons.close),
                onPressed: sending == null ? selection.clear : null,
              ),
              Expanded(
                child: Text(
                  sending == null
                      ? t.count(n: selection.length)
                      : context.t.monbooru.batch
                          .sending(sent: sending.$1, total: sending.$2),
                  style: context.theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: t.selectAll,
                icon: const Icon(Icons.select_all),
                onPressed:
                    sending == null ? () => selection.selectAll(posts()) : null,
              ),
              IconButton(
                tooltip: t.send,
                icon: sending == null
                    ? const Icon(Icons.cloud_upload_outlined)
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                onPressed: sending == null ? send : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

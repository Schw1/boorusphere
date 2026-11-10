import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/post_notes_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/monbooru_error.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/open_url.dart';
import 'package:boorusphere/presentation/utils/root_messenger.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/utils/extensions/number.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PostToolbox extends HookConsumerWidget {
  const PostToolbox(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewPadding = context.mediaQuery.viewPadding;
    final safePaddingBottom = useState(viewPadding.bottom);
    if (viewPadding.bottom > safePaddingBottom.value) {
      safePaddingBottom.value = viewPadding.bottom;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      height: safePaddingBottom.value + 86,
      alignment: Alignment.bottomRight,
      padding: EdgeInsets.only(bottom: safePaddingBottom.value + 8, right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PostNotesButton(post: post),
          PostFavoriteButton(post: post),
          PostDownloadButton(post: post),
          PostMonbooruButton(post: post),
          PostOpenLinkButton(post: post),
          PostDetailsButton(post: post),
        ],
      ),
    );
  }
}

/// Shows or hides translation notes; only there when the post has some.
class PostNotesButton extends HookConsumerWidget {
  const PostNotesButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(postNotesProvider(post)).value ?? const [];
    final visible = useValueListenable(postNotesVisible);
    if (notes.isEmpty) return const SizedBox.shrink();
    return IconButton(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      tooltip: context.t.notes.toggle,
      icon: Icon(Icons.translate,
          color: visible ? Colors.yellowAccent : Colors.white),
      onPressed: () => postNotesVisible.value = !visible,
    );
  }
}

class PostDetailsButton extends ConsumerWidget {
  const PostDetailsButton({
    super.key,
    required this.post,
  });

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      icon: const Icon(Icons.info),
      onPressed: () => context.router.push(PostDetailsRoute(
          post: post, session: ref.read(searchSessionProvider))),
    );
  }
}

class PostOpenLinkButton extends ConsumerWidget {
  const PostOpenLinkButton({
    super.key,
    required this.post,
  });

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverStateProvider).findById(post.serverId);
    // A browser cannot send the API token, so open the post page instead of
    // a file URL that needs it.
    final needsToken = server != null &&
        ServerAuthStore.tokenOf(server.id).isNotEmpty &&
        ServerAuthStore.isOwnOrigin(server, post.originalFile);
    // Galleries (nhentai) have no single file: open their page.
    final url = (needsToken || post.originalFile.isEmpty) &&
            post.postUrl.isNotEmpty
        ? post.postUrl
        : post.originalFile;
    return IconButton(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      icon: const Icon(Icons.link_outlined),
      onPressed: () => openWebUrl(url),
    );
  }
}

class PostFavoriteButton extends HookConsumerWidget {
  const PostFavoriteButton({
    super.key,
    required this.post,
  });

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(
        favoritePostStateProvider.select((it) => it.containsPost(post)));
    final animator =
        useAnimationController(duration: const Duration(milliseconds: 300));
    final animation = useAnimation(
        ColorTween(begin: Colors.white, end: Colors.pink.shade300)
            .animate(animator));
    isFav ? animator.forward() : animator.reverse();

    return IconButton(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      icon: isFav
          ? Icon(Icons.favorite, color: animation)
          : Icon(Icons.favorite_border, color: animation),
      onPressed: () {
        if (isFav) {
          ref.read(favoritePostStateProvider.notifier).remove(post);
        } else {
          ref.read(favoritePostStateProvider.notifier).save(post);
        }
      },
    );
  }
}

class PostDownloadButton extends HookConsumerWidget {
  const PostDownloadButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(downloadEntryStateProvider).getByPost(post);
    final progress = ref.watch(downloadProgressStateProvider).getById(entry.id);

    final pending = useState(false);

    // Galleries (nhentai) have no single file to download.
    if (post.originalFile.isEmpty) return const SizedBox.shrink();

    return Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: pending.value
              ? null
              : progress.status.isDownloading
                  ? progress.progress.ratio
                  : 0,
        ),
        IconButton(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          icon: Icon(progress.status.isDownloaded
              ? Icons.download_done
              : Icons.download),
          onPressed: pending.value ||
                  progress.status.isDownloaded ||
                  progress.status.isDownloading
              ? null
              : () async {
                  pending.value = true;
                  await DownloaderDialog.show(context, ref, post);
                  pending.value = false;
                },
          disabledColor: context.colorScheme.primary,
        ),
      ],
    );
  }
}

class PostMonbooruButton extends HookConsumerWidget {
  const PostMonbooruButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = MonbooruQueue.instance;
    final states = useValueListenable(queue.states);
    final state = states[post.viewId] ?? MonbooruPostState.unknown;
    final servers = ref.watch(serverStateProvider);
    final server = servers.findById(post.serverId);
    final isFromMonbooru =
        server != null && MonbooruJsonParser.isMonbooru(server);

    // Look the post up in Monbooru once it is shown.
    useEffect(() {
      if (!isFromMonbooru) queue.check(post, servers);
      return null;
    }, [post.viewId]);

    // Posts that already come from Monbooru are not sent back to it.
    if (isFromMonbooru) return const SizedBox.shrink();

    final t = context.t.monbooru;
    final Widget icon;
    final String tooltip;
    if (state.isBusy) {
      icon = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      tooltip = t.send;
    } else if (state.isInMonbooru) {
      icon = Icon(Icons.cloud_done, color: Colors.lightGreenAccent.shade200);
      tooltip = t.present;
    } else if (state.status == MonbooruPostStatus.failed) {
      icon = Icon(Icons.cloud_off_outlined, color: Colors.redAccent.shade100);
      tooltip = t.send;
    } else {
      icon = const Icon(Icons.cloud_upload_outlined);
      tooltip = t.send;
    }

    return IconButton(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      icon: icon,
      tooltip: tooltip,
      onPressed: state.isBusy
          ? null
          : () async {
              if (state.isInMonbooru &&
                  !await confirmSendDuplicate(context)) {
                return;
              }
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              final error = await queue.send(post, onReport: (report) {
                showRootSnackBar((c) => report.describe(c));
              });
              if (!context.mounted) return;
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(error?.describe(context) ?? t.sent),
                  duration: const Duration(seconds: 3),
                ));
            },
    );
  }
}

/// Asks before sending a post that is already in Monbooru.
Future<bool> confirmSendDuplicate(BuildContext context) async {
  final t = context.t.monbooru.duplicateDialog;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.title),
      content: Text(t.desc),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.sendAnyway),
        ),
      ],
    ),
  );
  return result ?? false;
}

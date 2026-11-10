import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Video playback is backed by media_kit (libmpv) instead of video_player,
/// because iOS' AVPlayer cannot play WebM/VP9, which boorus serve a lot.
class VideoPostSource {
  VideoPostSource({
    this.progress = const DownloadProgress('', 0, 0),
    this.player,
    this.controller,
    this.ready,
  });

  final DownloadProgress progress;
  final Player? player;
  final VideoController? controller;

  /// Completes (never throws) once the media has been opened or failed to open.
  final Future<void>? ready;

  VideoPostSource copyWith({
    DownloadProgress? progress,
    Player? player,
    VideoController? controller,
    Future<void>? ready,
  }) {
    return VideoPostSource(
      progress: progress ?? this.progress,
      player: player ?? this.player,
      controller: controller ?? this.controller,
      ready: ready ?? this.ready,
    );
  }

  @override
  bool operator ==(covariant VideoPostSource other) {
    if (identical(this, other)) return true;

    return other.progress == progress && other.player == player;
  }

  @override
  int get hashCode => progress.hashCode ^ player.hashCode;
}

VideoPostSource useVideoPostSource(
  WidgetRef ref, {
  required Post post,
  required bool active,
}) {
  return use(_VideoPostHook(ref, post: post, active: active));
}

class _VideoPostHook extends Hook<VideoPostSource> {
  const _VideoPostHook(this.ref, {required this.post, required this.active});

  final WidgetRef ref;
  final Post post;
  final bool active;

  @override
  _VideoPostState createState() => _VideoPostState();
}

class _VideoPostState extends HookState<VideoPostSource, _VideoPostHook> {
  _VideoPostState();

  VideoPostSource source = VideoPostSource();

  Future<void> createController() async {
    if (!hook.active) return;

    final headers = hook.ref.read(
      postHeadersFactoryProvider(hook.post, cookies: []),
    );

    final url = hook.post.content.url;
    final player = Player();
    final controller = VideoController(player);
    final ready = () async {
      try {
        await player.setPlaylistMode(PlaylistMode.single); // loop
        await player.open(Media(url, httpHeaders: headers), play: false);
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // the player may already be disposed, or the media may be unplayable
      }
    }();
    final prog = DownloadProgress(url, 1, 1);

    setState(() {
      source = source.copyWith(
        player: player,
        controller: controller,
        ready: ready,
        progress: prog,
      );
    });
  }

  void destroyController() {
    final player = source.player;
    source = VideoPostSource();
    if (player != null) {
      unawaited(player.dispose());
    }
  }

  @override
  void initHook() {
    super.initHook();
    createController();
  }

  @override
  void didUpdateHook(_VideoPostHook oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.active != hook.active) {
      destroyController();
      createController();
    }
  }

  @override
  VideoPostSource build(BuildContext context) => source;

  @override
  void dispose() {
    destroyController();
    super.dispose();
  }

  @override
  String get debugLabel => 'useVideoPost';
}

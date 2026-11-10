import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/fullscreen_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/post/hooks/video_post.dart';
import 'package:boorusphere/presentation/screens/post/post_placeholder_image.dart';
import 'package:boorusphere/presentation/screens/post/post_toolbox.dart';
import 'package:boorusphere/presentation/screens/post/quickbar.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:visibility_detector/visibility_detector.dart';

part 'video_seek_bar.dart';

class PostVideo extends StatefulWidget {
  const PostVideo({
    super.key,
    required this.post,
    required this.onToolboxVisibilityChange,
  });

  final Post post;
  final void Function(bool visible) onToolboxVisibilityChange;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  bool _visible = true;
  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey(widget.post.id),
      onVisibilityChanged: (info) {
        setState(() {
          _visible = info.visibleFraction > 0;
        });
      },
      child: _PostVideoContent(
        key: widget.key,
        post: widget.post,
        onToolboxVisibilityChange: widget.onToolboxVisibilityChange,
        isVisible: _visible,
      ),
    );
  }
}

/// Whether the detailed seek bar is shown; kept for the next video until the
/// app restarts.
bool _seekBarShown = false;

class _PostVideoContent extends HookConsumerWidget {
  const _PostVideoContent({
    super.key,
    required this.post,
    required this.onToolboxVisibilityChange,
    required this.isVisible,
  });

  final Post post;
  final bool isVisible;
  final void Function(bool visible) onToolboxVisibilityChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroMode = context.findAncestorWidgetOfExactType<HeroMode>();
    final isActive = (heroMode?.enabled ?? false) && isVisible;
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final contentSettings = ref.watch(contentSettingStateProvider);
    final fullscreen = ref.watch(fullscreenStateProvider);
    final shouldBlurExplicit =
        contentSettings.blurExplicit && !contentSettings.blurTimelineOnly;
    final shouldBlur = post.rating.isExplicit && shouldBlurExplicit;
    final isBlur = useState(shouldBlur);
    final blurNoticeAnimator = useAnimationController(
      duration: kThemeChangeDuration,
    );
    final showOverlay = useState(true);
    // don't show pause button on initial load
    final showPauseOverlay = useState(false);
    final isPlaying = useState(true);
    final hideTimer = useState(Timer(const Duration(seconds: 2), () {}));
    final seekBar = useState(_seekBarShown);
    final source = useVideoPostSource(ref, post: post, active: isActive);
    final player = isBlur.value ? null : source.player;
    final videoController = isBlur.value ? null : source.controller;

    onVisibilityChange(bool value) {
      showOverlay.value = value;
      showPauseOverlay.value = value;
      onToolboxVisibilityChange.call(value);
    }

    scheduleHide() {
      if (!context.mounted) return;
      hideTimer.value.cancel();
      hideTimer.value = Timer(const Duration(seconds: 2), () {
        if (!context.mounted) return;
        if (seekBar.value) {
          // Keep the toolbar and seek bar, only drop the play button and
          // the dimming.
          showPauseOverlay.value = false;
        } else {
          onVisibilityChange.call(false);
        }
      });
    }

    useEffect(() {
      Future(() {
        if (context.mounted && shouldBlur) {
          blurNoticeAnimator.forward();
        }
      });
    }, []);

    useEffect(() {
      if (player == null) return null;
      var cancelled = false;
      () async {
        await source.ready;
        if (cancelled || !context.mounted) return;
        // media_kit volume range is 0..100
        await player.setVolume(contentSettings.videoMuted ? 0 : 100);
        if (isPlaying.value && context.mounted && !cancelled) {
          await player.play();
          scheduleHide();
        }
      }();
      return () {
        cancelled = true;
      };
    }, [player]);

    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        Hero(
          key: ValueKey(post.viewId),
          tag: post.viewId,
          child: Center(
            child: AspectRatio(
              aspectRatio: post.aspectRatio,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  PostPlaceholderImage(
                    post: post,
                    headers: headers,
                    shouldBlur: isBlur.value,
                  ),
                  if (videoController != null)
                    Video(
                      controller: videoController,
                      controls: NoVideoControls,
                      fill: Colors.transparent,
                      fit: BoxFit.contain,
                    ),
                ],
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            onVisibilityChange.call(!showOverlay.value);
          },
          child: Container(
            color: showPauseOverlay.value ? Colors.black38 : Colors.transparent,
            child: Visibility(
              visible: showOverlay.value,
              replacement: const SizedBox.expand(),
              child: SafeArea(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Visibility(
                      visible: showPauseOverlay.value,
                      child: _PlayPauseOverlay(
                        isPlaying: isPlaying.value,
                        onPressed: () {
                          if (player != null) {
                            final playing = player.state.playing;
                            isPlaying.value = !playing;
                            playing ? player.pause() : player.play();
                            scheduleHide();
                          } else {
                            isPlaying.value = !isPlaying.value;
                          }
                        },
                      ),
                    ),
                    _ToolboxOverlay(
                      isPlaying: isPlaying.value,
                      source: source,
                      post: post,
                      isMuted: contentSettings.videoMuted,
                      isFullscreen: fullscreen,
                      showSeekBar: seekBar.value,
                      onSeekBarChange: (value) {
                        _seekBarShown = value;
                        seekBar.value = value;
                        showPauseOverlay.value = true;
                        scheduleHide();
                      },
                      onAutoHideRequest: scheduleHide,
                      onPlayChange: (value) {
                        isPlaying.value = value;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isBlur.value)
          Positioned(
            bottom: QuickBar.preferredBottomPosition(context) + 24,
            child: QuickBar.action(
              title: Text(context.t.unsafeContent),
              actionTitle: Text(context.t.unblur),
              onPressed: () {
                isBlur.value = false;
              },
            ),
          ),
      ],
    );
  }
}

class _ToolboxOverlay extends ConsumerWidget {
  const _ToolboxOverlay({
    required this.post,
    required this.source,
    required this.isPlaying,
    required this.isMuted,
    required this.isFullscreen,
    required this.showSeekBar,
    required this.onSeekBarChange,
    this.onAutoHideRequest,
    this.onPlayChange,
  });

  final bool isPlaying;
  final VideoPostSource source;
  final Post post;
  final bool isMuted;
  final bool isFullscreen;
  final bool showSeekBar;
  final void Function(bool value) onSeekBarChange;
  final void Function()? onAutoHideRequest;
  final void Function(bool value)? onPlayChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PostFavoriteButton(post: post),
            PostDownloadButton(post: post),
            PostMonbooruButton(post: post),
            IconButton(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              onPressed: () async {
                final mute = await ref
                    .read(contentSettingStateProvider.notifier)
                    .toggleVideoPlayerMute();
                await source.player?.setVolume(mute ? 0 : 100);
              },
              icon: Icon(isMuted ? Icons.volume_mute : Icons.volume_up),
            ),
            PostDetailsButton(post: post),
            IconButton(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              tooltip: context.t.video.seekBar,
              isSelected: showSeekBar,
              icon: const Icon(Icons.linear_scale),
              selectedIcon: const Icon(Icons.linear_scale, color: Colors.red),
              onPressed: () => onSeekBarChange(!showSeekBar),
            ),
            IconButton(
              color: Colors.white,
              icon: Icon(
                isFullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen_outlined,
              ),
              padding: const EdgeInsets.all(16),
              onPressed: () {
                ref
                    .read(fullscreenStateProvider.notifier)
                    .toggle(shouldLandscape: post.width > post.height);
                onAutoHideRequest?.call();
              },
            ),
          ],
        ),
        _Progress(
          source: source,
          detailed: showSeekBar,
          onInteraction: onAutoHideRequest,
        ),
      ],
    );
  }
}

class _PlayPauseOverlay extends StatelessWidget {
  const _PlayPauseOverlay({required this.isPlaying, required this.onPressed});

  final bool isPlaying;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black38,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: const EdgeInsets.all(8.0),
        color: Colors.white,
        iconSize: 72,
        icon: Icon(isPlaying ? Icons.pause_outlined : Icons.play_arrow),
        onPressed: onPressed,
      ),
    );
  }
}

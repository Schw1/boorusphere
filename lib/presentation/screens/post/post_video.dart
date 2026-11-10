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

class _Progress extends StatelessWidget {
  const _Progress({
    required this.source,
    this.detailed = false,
    this.onInteraction,
  });

  final VideoPostSource source;
  final bool detailed;
  final void Function()? onInteraction;

  double _getProgressValue(VideoPostSource src) {
    return src.progress.downloaded / (src.progress.totalSize ?? 1);
  }

  bool _isDownloading(VideoPostSource src) {
    final value = _getProgressValue(src);
    return value > 0 && value < 1;
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Stack(
        children: [
          if (_isDownloading(source))
            LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withAlpha(100),
              ),
              value: _getProgressValue(source),
              backgroundColor: Colors.transparent,
            ),
          LinearProgressIndicator(
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
            backgroundColor: Colors.white.withAlpha(20),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = source.player;
    if (player == null) return _buildLoading();

    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, snapshot) {
        final duration = snapshot.data ?? Duration.zero;
        if (duration <= Duration.zero) return _buildLoading();
        if (detailed) {
          return _DetailedSeekBar(
            player: player,
            duration: duration,
            onInteraction: onInteraction,
          );
        }
        return _SeekBar(player: player, duration: duration);
      },
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.duration});

  final Player player;
  final Duration duration;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragFraction;

  void _seekTo(double dx, double width, {bool dragging = false}) {
    if (width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0).toDouble();
    if (dragging) {
      setState(() => _dragFraction = fraction);
    }
    widget.player.seek(widget.duration * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _seekTo(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _seekTo(details.localPosition.dx, width, dragging: true),
            onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
            onHorizontalDragCancel: () => setState(() => _dragFraction = null),
            child: StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final fraction =
                    _dragFraction ??
                    (totalMs <= 0
                        ? 0.0
                        : (position.inMilliseconds / totalMs)
                              .clamp(0.0, 1.0)
                              .toDouble());
                return LinearProgressIndicator(
                  value: fraction,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  backgroundColor: Colors.white.withAlpha(20),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// `m:ss`, or `h:mm:ss` from one hour on.
String formatVideoTime(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// Larger seek bar with elapsed/total time and 10 s jump buttons.
class _DetailedSeekBar extends StatefulWidget {
  const _DetailedSeekBar({
    required this.player,
    required this.duration,
    this.onInteraction,
  });

  final Player player;
  final Duration duration;
  final void Function()? onInteraction;

  @override
  State<_DetailedSeekBar> createState() => _DetailedSeekBarState();
}

class _DetailedSeekBarState extends State<_DetailedSeekBar> {
  static const _jump = Duration(seconds: 10);
  double? _dragMs;

  void _jumpBy(Duration offset) {
    final target = widget.player.state.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > widget.duration ? widget.duration : target);
    widget.player.seek(clamped);
    widget.onInteraction?.call();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.toDouble();
    const textStyle = TextStyle(
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black38),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          initialData: widget.player.state.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final valueMs = (_dragMs ?? position.inMilliseconds.toDouble())
                .clamp(0.0, totalMs <= 0 ? 0.0 : totalMs)
                .toDouble();
            return Row(
              children: [
                IconButton(
                  color: Colors.white,
                  tooltip: context.t.video.back10,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _jumpBy(-_jump),
                ),
                Text(
                  formatVideoTime(Duration(milliseconds: valueMs.round())),
                  style: textStyle,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.red,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.red,
                      overlayColor: Colors.red.withAlpha(40),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: totalMs <= 0 ? 1 : totalMs,
                      value: valueMs,
                      onChangeStart: (v) => setState(() => _dragMs = v),
                      onChanged: (v) {
                        setState(() => _dragMs = v);
                        widget.player.seek(Duration(milliseconds: v.round()));
                      },
                      onChangeEnd: (v) {
                        widget.player.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragMs = null);
                        widget.onInteraction?.call();
                      },
                    ),
                  ),
                ),
                Text(formatVideoTime(widget.duration), style: textStyle),
                IconButton(
                  color: Colors.white,
                  tooltip: context.t.video.forward10,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _jumpBy(_jump),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

part of 'post_video.dart';

// Progress bar and the detailed seek bar of the video player.

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

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/post_notes.dart';
import 'package:boorusphere/presentation/provider/post_notes_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Boxes over the translated speech bubbles of [post]; tapping one shows
/// its text. Drawn for the unzoomed image only ([zoomed] hides them).
class PostNotesOverlay extends HookConsumerWidget {
  const PostNotesOverlay({super.key, required this.post, required this.zoomed});

  final Post post;
  final ValueListenable<bool> zoomed;

  /// Where the image is drawn in a box of [size] (BoxFit.contain).
  static Rect imageRect(Size size, double imageWidth, double imageHeight) {
    if (imageWidth <= 0 || imageHeight <= 0) return Offset.zero & size;
    final scale = size.width / imageWidth < size.height / imageHeight
        ? size.width / imageWidth
        : size.height / imageHeight;
    final w = imageWidth * scale, h = imageHeight * scale;
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(postNotesProvider(post)).value ?? const [];
    final visible = useValueListenable(postNotesVisible);
    final isZoomed = useValueListenable(zoomed);
    final selected = useState<int?>(null);
    if (notes.isEmpty || !visible || isZoomed || post.width <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final image = imageRect(
          size,
          post.width.toDouble(),
          post.height.toDouble(),
        );
        final scale = image.width / post.width;
        Rect boxOf(PostNote note) => Rect.fromLTWH(
          image.left + note.x * scale,
          image.top + note.y * scale,
          note.width * scale,
          note.height * scale,
        );

        final index = selected.value;
        return Stack(
          children: [
            for (var i = 0; i < notes.length; i++)
              Positioned.fromRect(
                rect: boxOf(notes[i]),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => selected.value = selected.value == i ? null : i,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.yellow.withValues(alpha: 0.12),
                      border: Border.all(
                        color: i == index
                            ? Colors.yellowAccent
                            : Colors.black54,
                        width: i == index ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            if (index != null && index < notes.length)
              _Bubble(
                text: notes[index].text,
                box: boxOf(notes[index]),
                area: size,
                onTap: () => selected.value = null,
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.box,
    required this.area,
    required this.onTap,
  });

  final String text;
  final Rect box;
  final Size area;
  final VoidCallback onTap;

  static const _maxWidth = 280.0;

  @override
  Widget build(BuildContext context) {
    final width = _maxWidth.clamp(0.0, area.width - 16).toDouble();
    final left = box.left.clamp(8.0, area.width - width - 8).toDouble();
    // below the box if there's room in the lower half, else above it
    final below = box.bottom < area.height * 0.6;
    return Positioned(
      left: left,
      width: width,
      top: below ? box.bottom + 6 : null,
      bottom: below ? null : area.height - box.top + 6,
      child: GestureDetector(
        onTap: onTap,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Colors.yellow.shade50,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              text,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}

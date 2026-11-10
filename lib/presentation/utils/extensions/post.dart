import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/utils/file_md5.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';

extension PostExt on Post {
  bool get hasCategorizedTags => [
    ...tagsArtist,
    ...tagsCharacter,
    ...tagsCopyright,
    ...tagsGeneral,
    ...tagsMeta,
  ].isNotEmpty;

  Set<String> get allTags => {
    ...tagsArtist,
    ...tagsCharacter,
    ...tagsCopyright,
    ...tagsGeneral,
    ...tagsMeta,
    ...tags,
  };

  String get describeTags => allTags.join(' ');

  double get aspectRatio {
    if (prescreensize.hasPixels) {
      return prescreensize.aspectRatio;
    } else if (sampleSize.hasPixels) {
      return sampleSize.aspectRatio;
    } else {
      return originalSize.aspectRatio;
    }
  }

  PixelSize get originalSize => PixelSize(width: width, height: height);

  PixelSize get sampleSize =>
      PixelSize(width: sampleWidth, height: sampleHeight);

  PixelSize get prescreensize =>
      PixelSize(width: previewWidth, height: previewHeight);

  BooruRating get rating => BooruRating.parse(rateValue);

  Content get content {
    final sample = sampleFile.asContent();
    final original = originalFile.asContent();
    if (sample.isPhoto && original.isVideo || sample.isUnsupported) {
      return original;
    }

    return sample;
  }

  String get viewId {
    return '$id-$serverId';
  }

  bool get isReserved {
    return id < 0;
  }

  /// md5 of the original file, from the booru or from the file URL.
  String get fileMd5 => md5.isNotEmpty ? md5 : FileMd5.fromUrl(originalFile);

  /// Multi-page archive (Monbooru CBZ).
  bool get isArchive => pageCount > 0;

  /// URL the viewer shows: the original file with "Load original" (not
  /// for archives, whose original is the .cbz), otherwise the sample.
  String viewerUrl({required bool loadOriginal}) =>
      loadOriginal && !isArchive ? originalFile : content.url;

  /// Size to decode [url] to in the viewer, or null to keep it as it is.
  ///
  /// Decoded pictures take width × height × 4 bytes: a 10000 × 10000
  /// original is 400 MB, which gets the app killed on iOS. Pictures larger
  /// than [maxViewerSide] on their longest side are scaled down to it.
  /// Unknown sizes are left alone.
  PixelSize? viewerDecodeSize(String url) {
    final size = url == originalFile
        ? originalSize
        : url == sampleFile
        ? sampleSize
        : const PixelSize();
    if (size.width <= 0 || size.height <= 0) return null;
    final longest = size.width > size.height ? size.width : size.height;
    if (longest <= maxViewerSide) return null;
    final scale = maxViewerSide / longest;
    return PixelSize(
      width: (size.width * scale).round().clamp(1, maxViewerSide),
      height: (size.height * scale).round().clamp(1, maxViewerSide),
    );
  }
}

/// Longest side, in pixels, a picture in the viewer is decoded to.
const maxViewerSide = 4096;

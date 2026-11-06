import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

/// Copies finished downloads into the iOS Photos library (optional setting).
class PhotosSaver {
  static const _images = {'.jpg', '.jpeg', '.png', '.gif', '.heic', '.webp'};
  // The Photos library only accepts these containers; WebM etc. stay in Files.
  static const _videos = {'.mp4', '.m4v', '.mov'};

  static final _saved = <String>{};

  static bool isSupported(String path) {
    final ext = p.extension(path).toLowerCase();
    return _images.contains(ext) || _videos.contains(ext);
  }

  /// Asks for permission to add to the Photos library. Returns true if granted.
  static Future<bool> requestAccess() async {
    try {
      if (await Gal.hasAccess()) return true;
      return await Gal.requestAccess();
    } catch (e) {
      debugPrint('PhotosSaver.requestAccess: $e');
      return false;
    }
  }

  /// Saves [path] to Photos once per download [id]. Returns true on success.
  static Future<bool> save(String id, String path) async {
    if (_saved.contains(id)) return true;
    final ext = p.extension(path).toLowerCase();
    try {
      if (!await requestAccess()) return false;
      if (_images.contains(ext)) {
        await Gal.putImage(path);
      } else if (_videos.contains(ext)) {
        await Gal.putVideo(path);
      } else {
        return false;
      }
      _saved.add(id);
      return true;
    } catch (e) {
      debugPrint('PhotosSaver.save($path): $e');
      return false;
    }
  }
}

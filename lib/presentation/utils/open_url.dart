import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// [url] as a web address, or null when it isn't one.
///
/// Links shown with a post (source, file and page URLs) come from the
/// server. Only http(s) is opened: a source can be free text, or name
/// another scheme (`tel:`, another app's URL scheme) that the app must not
/// hand to the system.
Uri? webUriOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// Opens [url] in the browser if it is a web address. Returns whether it
/// was opened.
Future<bool> openWebUrl(String url) async {
  final uri = webUriOf(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openWebUrl: $e');
    return false;
  }
}

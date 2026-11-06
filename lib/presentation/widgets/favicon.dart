import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Server icon. Tries the site's own /favicon.ico first (works for
/// self-hosted servers such as Monbooru); only public hosts fall back to the
/// DuckDuckGo icon service, so local addresses are never sent to it.
class Favicon extends ConsumerWidget {
  const Favicon({
    super.key,
    required this.url,
    this.size,
    this.iconSize,
    this.shape,
  });

  final String url;
  final double? size;
  final double? iconSize;
  final BoxShape? shape;

  List<String> get candidates {
    final uri = url.toUri();
    if (!uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const [];
    }
    final origin = '${uri.scheme}://${uri.authority}';
    return [
      '$origin/favicon.ico',
      if (!ServerAuthStore.isLocalHost(uri.host))
        'https://icons.duckduckgo.com/ip3/${uri.host}.ico',
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconSize = this.iconSize ?? context.iconTheme.size;
    // Same User-Agent as image requests: the shared HTTP client strips the
    // default Dart one, and many proxies reject requests without any.
    final headers = HeadersFactory.builder()
        .setUserAgent(ref.watch(versionRepoProvider).current)
        .build()
      ..['Accept'] = 'image/*';
    final fallbackWidget = Icon(Icons.public, size: iconSize);
    return SizedBox(
      width: size ?? context.iconTheme.size,
      height: size ?? context.iconTheme.size,
      child: Center(
        child: _build(candidates, headers, iconSize, fallbackWidget),
      ),
    );
  }

  Widget _build(List<String> urls, Map<String, String> headers,
      double? iconSize, Widget fallbackWidget) {
    if (urls.isEmpty) return fallbackWidget;
    return ExtendedImage.network(
      urls.first,
      headers: headers,
      width: iconSize,
      height: iconSize,
      shape: shape,
      fit: BoxFit.contain,
      printError: false,
      loadStateChanged: (state) => switch (state.extendedImageLoadState) {
        LoadState.completed => state.completedWidget,
        LoadState.failed =>
          _build(urls.sublist(1), headers, iconSize, fallbackWidget),
        _ => fallbackWidget,
      },
    );
  }
}

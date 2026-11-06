import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:flutter/widgets.dart';

extension MonbooruErrorText on MonbooruError {
  String describe(BuildContext context) {
    final t = context.t.monbooru.error;
    return switch (kind) {
      MonbooruErrorKind.notConfigured => t.notConfigured,
      MonbooruErrorKind.noUrl => t.noUrl,
      MonbooruErrorKind.unreachable => t.unreachable(detail: detail),
      MonbooruErrorKind.invalidToken => t.invalidToken,
      MonbooruErrorKind.noWriteScope => t.noWriteScope,
      MonbooruErrorKind.unavailable => t.unavailable,
      MonbooruErrorKind.apiDisabled => t.apiDisabled,
      MonbooruErrorKind.http => t.http(code: detail),
    };
  }
}

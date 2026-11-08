import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
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

extension MonbooruSendReportText on MonbooruSendReport {
  String describe(BuildContext context) {
    final t = context.t.monbooru.result;
    final sendError = error;
    if (sendError != null) return sendError.describe(context);
    if (unconfirmed) return t.unconfirmed;
    return switch (outcome) {
      MonbooruOutcome.added => t.added,
      MonbooruOutcome.duplicate => t.duplicate,
      MonbooruOutcome.skipped => t.skipped,
      MonbooruOutcome.failed =>
        jobError.isEmpty ? t.failed : t.failedWith(error: jobError),
      null => t.unconfirmed,
    };
  }
}

extension MonbooruBatchReportText on MonbooruBatchReport {
  String describe(BuildContext context) {
    final t = context.t.monbooru.batch;
    final parts = [
      if (added > 0) t.added(n: added),
      if (duplicate + alreadyThere > 0)
        t.alreadyThere(n: duplicate + alreadyThere),
      if (skipped > 0) t.skipped(n: skipped),
      if (failed > 0) t.failed(n: failed),
      if (unconfirmed > 0) t.unconfirmed(n: unconfirmed),
    ];
    final summary = parts.isEmpty ? t.nothing : parts.join(', ');
    final firstError = error;
    return firstError == null
        ? summary
        : '$summary (${firstError.describe(context)})';
  }
}

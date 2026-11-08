import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/signature_expiry.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// "in 5 h" / "in 2 days", plus the local date and time.
String describeSignatureExpiry(BuildContext context, DateTime expiry) {
  final t = context.t.signature;
  final local = expiry.toLocal();
  final left = expiry.difference(DateTime.now());
  final relative = left.inHours < 24
      ? t.inHours(n: left.inHours.clamp(0, 23))
      : t.inDays(n: (left.inHours / 24).floor());
  return '$relative (${DateFormat.MMMEd().add_Hm().format(local)})';
}

/// Warning shown at the top of the timeline when the sideloading signature
/// is about to expire.
class SignatureBanner extends HookConsumerWidget {
  const SignatureBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiry = ref.watch(signatureExpiryProvider).value;
    final dismissed = useState(signatureBannerDismissed);
    if (dismissed.value ||
        !shouldWarnAboutSignature(expiry, DateTime.now().toUtc())) {
      return const SizedBox.shrink();
    }

    final t = context.t.signature;
    return Card(
      elevation: 0,
      color: context.colorScheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    color: context.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.expires(when: describeSignatureExpiry(context, expiry!)),
                    style: context.theme.textTheme.titleSmall?.copyWith(
                      color: context.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4),
              child: Text(
                t.desc,
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onErrorContainer,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  signatureBannerDismissed = true;
                  dismissed.value = true;
                },
                child: Text(t.dismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

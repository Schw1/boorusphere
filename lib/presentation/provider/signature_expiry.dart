import 'package:boorusphere/data/repository/env/provisioning_profile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Expiry of the app's signature (iOS sideloading), null when unknown.
final signatureExpiryProvider = FutureProvider<DateTime?>(
  (ref) => ProvisioningProfile.loadExpiration(),
);

/// Warn this long before the signature expires. Free Apple IDs sign for
/// 7 days, so this is the last two days of a signature.
const kSignatureWarning = Duration(days: 2);

/// Set when the banner was dismissed; it comes back on the next app start.
bool signatureBannerDismissed = false;

/// Whether to warn about [expiry] at [now].
bool shouldWarnAboutSignature(DateTime? expiry, DateTime now) {
  if (expiry == null) return false;
  return expiry.difference(now) <= kSignatureWarning;
}

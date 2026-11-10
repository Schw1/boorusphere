import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Reads the expiry date of the provisioning profile the app was signed with.
///
/// Sideloaded apps (Sideloadly, AltStore) carry an `embedded.mobileprovision`
/// in the app bundle. With a free Apple ID it expires after 7 days; after that
/// iOS refuses to launch the app until it is installed again.
class ProvisioningProfile {
  const ProvisioningProfile._();

  static final _expiration = RegExp(
    r'<key>\s*ExpirationDate\s*</key>\s*<date>\s*([^<\s]+)\s*</date>',
  );

  /// Extracts `ExpirationDate` from the raw profile. The file is a signed
  /// CMS container, but the property list inside is stored as plain XML.
  @visibleForTesting
  static DateTime? parseExpiration(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final match = _expiration.firstMatch(text);
    if (match == null) return null;
    return DateTime.tryParse(match.group(1)!)?.toUtc();
  }

  /// Path of the profile inside the running app bundle (`Runner.app`).
  static String get _path => p.join(
    File(Platform.resolvedExecutable).parent.path,
    'embedded.mobileprovision',
  );

  /// Expiry of the current signature, or null when unknown (not iOS, no
  /// profile in the bundle, unreadable file).
  static Future<DateTime?> loadExpiration() async {
    if (!Platform.isIOS) return null;
    try {
      final file = File(_path);
      if (!file.existsSync()) return null;
      return parseExpiration(await file.readAsBytes());
    } catch (e) {
      debugPrint('ProvisioningProfile.loadExpiration: $e');
      return null;
    }
  }
}

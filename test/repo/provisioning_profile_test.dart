import 'dart:convert';

import 'package:boorusphere/data/repository/env/provisioning_profile.dart';
import 'package:boorusphere/presentation/provider/signature_expiry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A profile is a signed CMS blob with the plist as plain XML inside.
List<int> fakeProfile(String plistBody) => [
      0x30, 0x82, 0x1f, 0x9e, 0x06, 0x09, 0x2a, 0x86, 0xff, 0x00, //
      ...latin1.encode('<?xml version="1.0" encoding="UTF-8"?>\n'
          '<plist version="1.0"><dict>$plistBody</dict></plist>'),
      0x00, 0xa0, 0x82, 0x0d, 0xff,
    ];

void main() {
  group('ProvisioningProfile.parseExpiration', () {
    test('reads ExpirationDate', () {
      final bytes = fakeProfile('''
        <key>AppIDName</key><string>Boorusphere</string>
        <key>CreationDate</key><date>2026-11-01T10:00:00Z</date>
        <key>ExpirationDate</key>
        <date>2026-11-08T10:00:00Z</date>
        <key>Name</key><string>iOS Team Provisioning Profile</string>''');
      expect(ProvisioningProfile.parseExpiration(bytes),
          DateTime.utc(2026, 11, 8, 10));
    });

    test('no date', () {
      expect(ProvisioningProfile.parseExpiration(fakeProfile('')), isNull);
      expect(ProvisioningProfile.parseExpiration([1, 2, 3]), isNull);
    });

    test('broken date', () {
      final bytes = fakeProfile(
          '<key>ExpirationDate</key><date>not a date</date>');
      expect(ProvisioningProfile.parseExpiration(bytes), isNull);
    });
  });

  group('shouldWarnAboutSignature', () {
    final now = DateTime.utc(2026, 11, 8, 12);
    test('unknown expiry', () {
      expect(shouldWarnAboutSignature(null, now), isFalse);
    });
    test('far away', () {
      expect(shouldWarnAboutSignature(now.add(const Duration(days: 5)), now),
          isFalse);
    });
    test('within two days', () {
      expect(
          shouldWarnAboutSignature(now.add(const Duration(hours: 47)), now),
          isTrue);
      expect(shouldWarnAboutSignature(now.add(const Duration(hours: 1)), now),
          isTrue);
    });
  });
}

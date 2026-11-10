import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLocalHost', () {
    test('local network names and addresses', () {
      for (final host in [
        'localhost',
        'nas',
        'raspberrypi',
        'booru.local',
        'nas.lan',
        'nas.home.arpa',
        'monbooru.fritz.box',
        'NAS.FRITZ.BOX',
        'nas.fritz.box.',
        'booru.internal',
        'pi.localdomain',
        '10.0.0.5',
        '127.0.0.1',
        '192.168.1.20',
        '172.20.0.3',
        '100.101.102.103',
        '169.254.10.1',
        '::1',
        '[::1]',
        'fd12:3456:789a::1',
        'fc00::5',
        'fe80::1',
        'fe80::1%en0',
      ]) {
        expect(ServerAuthStore.isLocalHost(host), true, reason: host);
      }
    });

    test('public names and addresses', () {
      for (final host in [
        'danbooru.donmai.us',
        'booru.example.org',
        'fritz.box.example.com',
        'local.example.com',
        '8.8.8.8',
        '172.32.0.1',
        '100.128.0.1',
        '2001:4860:4860::8888',
        '',
      ]) {
        expect(ServerAuthStore.isLocalHost(host), false, reason: host);
      }
    });

    test('plain HTTP is only flagged outside the local network', () {
      expect(
        ServerAuthStore.isInsecureRemote('http://nas.fritz.box:8455'),
        false,
      );
      expect(ServerAuthStore.isInsecureRemote('http://[fd00::2]:8455'), false);
      expect(
        ServerAuthStore.isInsecureRemote('http://booru.example.org'),
        true,
      );
      expect(
        ServerAuthStore.isInsecureRemote('https://booru.example.org'),
        false,
      );
    });
  });

  group('movedServers', () {
    const mon = Server(id: 'Mon', homepage: 'https://mon.example.org');

    test('a server restored with another address has moved', () {
      expect(
        ServerAuthStore.movedServers(
          [mon],
          [mon.copyWith(homepage: 'https://evil.example.com')],
        ),
        {'Mon'},
      );
    });

    test('another API address counts too', () {
      expect(
        ServerAuthStore.movedServers(
          [mon],
          [mon.copyWith(apiAddr: 'https://api.example.com')],
        ),
        {'Mon'},
      );
    });

    test('the same origin with another path or case has not moved', () {
      expect(
        ServerAuthStore.movedServers(
          [mon],
          [mon.copyWith(homepage: 'https://MON.example.org/')],
        ),
        isEmpty,
      );
    });

    test('new and removed servers are not moved', () {
      expect(
        ServerAuthStore.movedServers(
          [mon],
          [const Server(id: 'Other', homepage: 'https://other.example.org')],
        ),
        isEmpty,
      );
    });
  });
}

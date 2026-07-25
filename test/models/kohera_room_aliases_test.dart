import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_aliases.dart';

void main() {
  group('KoheraRoomAliases', () {
    test('nonCanonical excludes the canonical alias', () {
      const a = KoheraRoomAliases(
        roomId: '!r:example.com',
        aliases: ['#a:example.com', '#b:example.com', '#c:example.com'],
        canonicalAlias: '#a:example.com',
        canEdit: true,
        homeserverDomain: 'example.com',
      );
      expect(a.nonCanonical, ['#b:example.com', '#c:example.com']);
    });

    test('nonCanonical returns all when canonical unset', () {
      const a = KoheraRoomAliases(
        roomId: '!r:example.com',
        aliases: ['#a:example.com', '#b:example.com'],
        canonicalAlias: null,
        canEdit: false,
        homeserverDomain: 'example.com',
      );
      expect(a.nonCanonical, ['#a:example.com', '#b:example.com']);
    });

    test('nonCanonical returns all when canonical is empty string', () {
      const a = KoheraRoomAliases(
        roomId: '!r:example.com',
        aliases: ['#a:example.com'],
        canonicalAlias: '',
        canEdit: true,
        homeserverDomain: 'example.com',
      );
      expect(a.nonCanonical, ['#a:example.com']);
    });

    test('equality considers all fields', () {
      const a = KoheraRoomAliases(
        roomId: '!r:example.com',
        aliases: ['#a:example.com'],
        canonicalAlias: '#a:example.com',
        canEdit: true,
        homeserverDomain: 'example.com',
      );
      const b = KoheraRoomAliases(
        roomId: '!r:example.com',
        aliases: ['#a:example.com'],
        canonicalAlias: '#a:example.com',
        canEdit: true,
        homeserverDomain: 'example.com',
      );
      const c = KoheraRoomAliases(
        roomId: '!r:example.com',
        aliases: ['#a:example.com'],
        canonicalAlias: '#a:example.com',
        canEdit: false,
        homeserverDomain: 'example.com',
      );
      expect(a, b);
      expect(a, isNot(c));
      expect(a.hashCode, b.hashCode);
    });
  });
}

// coverage:ignore-file

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/backend.dart';

void main() {
  group('RoomDto', () {
    test('toMap / fromMap round-trip', () {
      const dto = RoomDto(
        roomId: '!test:server',
        name: 'Test Room',
        displayName: 'Test Room',
        canonicalAlias: '#test:server',
        avatarMxc: 'mxc://server/abc',
        topic: 'A topic',
        encrypted: true,
        isDirect: false,
        membership: 'Membership.join',
        unreadCount: 5,
        notificationCount: 3,
        highlightCount: 1,
        lastEventId: r'$event1',
        lastEventTs: 1700000000000,
        muted: false,
        pushRuleState: 'PushRuleState.notify',
      );

      final map = dto.toMap();
      final restored = RoomDto.fromMap(map);

      expect(restored.roomId, '!test:server');
      expect(restored.name, 'Test Room');
      expect(restored.encrypted, true);
      expect(restored.unreadCount, 5);
      expect(restored.lastEventTs, 1700000000000);
      expect(restored.pushRuleState, 'PushRuleState.notify');
    });

    test('nullable fields handle null', () {
      const dto = RoomDto(
        roomId: '!empty:server',
        name: '',
        displayName: '',
        encrypted: false,
        isDirect: false,
        membership: 'Membership.leave',
        unreadCount: 0,
        notificationCount: 0,
        highlightCount: 0,
        muted: false,
        pushRuleState: 'PushRuleState.notify',
      );

      final restored = RoomDto.fromMap(dto.toMap());

      expect(restored.canonicalAlias, isNull);
      expect(restored.avatarMxc, isNull);
      expect(restored.topic, isNull);
      expect(restored.lastEventId, isNull);
      expect(restored.lastEventTs, isNull);
    });
  });

  group('AccountDto', () {
    test('toMap / fromMap round-trip', () {
      const dto = AccountDto(
        clientName: 'default',
        userId: '@alice:server',
        deviceId: 'DEVICE123',
        homeserver: 'https://matrix.server',
        displayName: 'Alice',
        avatarMxc: 'mxc://server/alice',
        isLoggedIn: true,
      );

      final restored = AccountDto.fromMap(dto.toMap());

      expect(restored.clientName, 'default');
      expect(restored.userId, '@alice:server');
      expect(restored.deviceId, 'DEVICE123');
      expect(restored.displayName, 'Alice');
      expect(restored.isLoggedIn, true);
    });

    test('handles null avatar', () {
      const dto = AccountDto(
        clientName: 'default',
        userId: '@bob:server',
        deviceId: 'DEV',
        homeserver: 'https://server',
        displayName: 'Bob',
        isLoggedIn: false,
      );

      final restored = AccountDto.fromMap(dto.toMap());
      expect(restored.avatarMxc, isNull);
      expect(restored.isLoggedIn, false);
    });
  });
}

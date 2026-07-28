import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';

void main() {
  group('RoomSnapshot', () {
    test('round-trips with avatar', () {
      const snap = RoomSnapshot(
        roomId: '!room:example.com',
        displayname: 'Project',
        avatarMxc: 'mxc://example.com/abc',
      );

      final decoded = RoomSnapshot.decode(snap.encode());

      expect(decoded.roomId, '!room:example.com');
      expect(decoded.displayname, 'Project');
      expect(decoded.avatarMxc, 'mxc://example.com/abc');
    });

    test('round-trips without avatar', () {
      const snap = RoomSnapshot(
        roomId: '!room:example.com',
        displayname: 'DM',
      );

      final map = jsonDecode(snap.encode()) as Map<String, dynamic>;
      expect(map.containsKey('avatarMxc'), isFalse);
      expect(map.containsKey('avatarPath'), isFalse);

      final decoded = RoomSnapshot.decode(snap.encode());
      expect(decoded.avatarMxc, isNull);
      expect(decoded.avatarPath, isNull);
    });

    test('round-trips with avatarPath', () {
      const snap = RoomSnapshot(
        roomId: '!room:example.com',
        displayname: 'Project',
        avatarMxc: 'mxc://srv/abc',
        avatarPath: '/var/group/avatars/!room.png',
      );

      final decoded = RoomSnapshot.decode(snap.encode());
      expect(decoded.avatarMxc, 'mxc://srv/abc');
      expect(decoded.avatarPath, '/var/group/avatars/!room.png');
    });

    test('equality is by roomId only', () {
      const a = RoomSnapshot(roomId: '!r:s', displayname: 'A', avatarMxc: 'x');
      const b = RoomSnapshot(roomId: '!r:s', displayname: 'B');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}

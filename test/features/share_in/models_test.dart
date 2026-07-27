import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/pending_share.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';

void main() {
  group('PendingShare', () {
    test('text share round-trips through JSON', () {
      const share = PendingShare(
        id: 'abc',
        targetRoomId: '!room:example.com',
        accountId: 'default',
        kind: PendingShareKind.text,
        text: 'hello',
        createdAt: 1700000000000,
      );

      final encoded = share.encode();
      final decoded = PendingShare.decode(encoded);

      expect(decoded.id, 'abc');
      expect(decoded.targetRoomId, '!room:example.com');
      expect(decoded.accountId, 'default');
      expect(decoded.kind, PendingShareKind.text);
      expect(decoded.text, 'hello');
      expect(decoded.filePath, isNull);
      expect(decoded.createdAt, 1700000000000);
    });

    test('file share round-trips with all optional fields', () {
      const share = PendingShare(
        id: 'xyz',
        targetRoomId: '!room:example.com',
        accountId: 'work',
        kind: PendingShareKind.file,
        filePath: '/tmp/staged.img',
        mimeType: 'image/png',
        originalFileName: 'photo.png',
        createdAt: 1700000000001,
      );

      final decoded = PendingShare.decode(share.encode());

      expect(decoded.kind, PendingShareKind.file);
      expect(decoded.filePath, '/tmp/staged.img');
      expect(decoded.mimeType, 'image/png');
      expect(decoded.originalFileName, 'photo.png');
      expect(decoded.text, isNull);
    });

    test('toJson omits null optional fields', () {
      const share = PendingShare(
        id: 'id1',
        targetRoomId: '!r:srv',
        accountId: 'default',
        kind: PendingShareKind.text,
        text: 'hi',
        createdAt: 0,
      );

      final map = jsonDecode(share.encode()) as Map<String, dynamic>;
      expect(map.containsKey('filePath'), isFalse);
      expect(map.containsKey('mimeType'), isFalse);
      expect(map.containsKey('originalFileName'), isFalse);
      expect(map.containsKey('text'), isTrue);
    });

    test('equality is by id only', () {
      const a = PendingShare(
        id: 'id',
        targetRoomId: '!a:srv',
        accountId: 'default',
        kind: PendingShareKind.text,
        text: 'a',
        createdAt: 0,
      );
      const b = PendingShare(
        id: 'id',
        targetRoomId: '!b:srv',
        accountId: 'other',
        kind: PendingShareKind.file,
        filePath: '/x',
        createdAt: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

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

      final decoded = RoomSnapshot.decode(snap.encode());
      expect(decoded.avatarMxc, isNull);
    });

    test('equality is by roomId only', () {
      const a = RoomSnapshot(roomId: '!r:s', displayname: 'A', avatarMxc: 'x');
      const b = RoomSnapshot(roomId: '!r:s', displayname: 'B');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}

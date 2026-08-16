import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/adapters/in_process_backend.dart';
import 'package:kohera/core/backend/adapters/stub_worker_handler.dart';
import 'package:kohera/core/backend/adapters/worker_backend.dart';
import 'package:kohera/core/backend/dto/member_dto.dart';
import 'package:kohera/core/backend/dto/user_dto.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

/// Verifies the room management, room state, and members/users ops (#994):
///   - MemberDto / UserDto serialization round-trips.
///   - StubWorkerHandler round-trips every op without error.
///   - InProcessBackend no-op stubs return neutral values.
///   - WorkerBackend wires every op through _call() and decodes results.

void main() {
  group('MemberDto serialization', () {
    test('toMap / fromMap round-trips all fields', () {
      const dto = MemberDto(
        userId: '@alice:example.org',
        displayName: 'Alice',
        avatarMxc: 'mxc://example.org/abc',
        powerLevel: 50,
      );
      final m = dto.toMap();
      expect(m['userId'], '@alice:example.org');
      expect(m['displayName'], 'Alice');
      expect(m['avatarMxc'], 'mxc://example.org/abc');
      expect(m['powerLevel'], 50);
      final decoded = MemberDto.fromMap(m);
      expect(decoded.userId, dto.userId);
      expect(decoded.displayName, dto.displayName);
      expect(decoded.avatarMxc, dto.avatarMxc);
      expect(decoded.powerLevel, dto.powerLevel);
    });

    test('handles null avatar', () {
      const dto = MemberDto(
        userId: '@bob:b.org',
        displayName: 'bob',
        powerLevel: 0,
      );
      expect(dto.toMap()['avatarMxc'], isNull);
      expect(MemberDto.fromMap(dto.toMap()).avatarMxc, isNull);
    });
  });

  group('UserDto serialization', () {
    test('toMap / fromMap round-trips all fields', () {
      const dto = UserDto(
        userId: '@carol:c.org',
        displayName: 'Carol',
        avatarMxc: 'mxc://c.org/x',
      );
      final decoded = UserDto.fromMap(dto.toMap());
      expect(decoded.userId, '@carol:c.org');
      expect(decoded.displayName, 'Carol');
      expect(decoded.avatarMxc, 'mxc://c.org/x');
    });

    test('handles null avatar', () {
      const dto = UserDto(userId: '@dan:d.org', displayName: 'dan');
      expect(UserDto.fromMap(dto.toMap()).avatarMxc, isNull);
    });
  });

  group('StubWorkerHandler room mgmt + state + members ops', () {
    late StubWorkerHandler handler;
    const emit = _noopEmit;

    setUp(() => handler = StubWorkerHandler());
    tearDown(() => handler.dispose());

    Future<BackendResult> call(String op, Map<String, dynamic> args) =>
        handler.handle(BackendCall(id: 0, op: op, args: args), emit);

    test('roomMgmt.* void ops return ok empty', () async {
      for (final op in [
        'roomMgmt.leave',
        'roomMgmt.join',
        'roomMgmt.invite',
        'roomMgmt.kick',
        'roomMgmt.ban',
        'roomMgmt.unban',
      ]) {
        final r = await call(op, {'roomId': '!r:s', 'userId': '@u:s'});
        expect(r.ok, true, reason: op);
        expect(r.data, isEmpty, reason: op);
      }
    });

    test('roomMgmt.setName / setTopic / setAvatar return ok empty', () async {
      for (final op in ['roomMgmt.setName', 'roomMgmt.setTopic']) {
        final r = await call(op, {'roomId': '!r:s', 'name': 'n'});
        expect(r.ok, true, reason: op);
      }
      final r = await call('roomMgmt.setAvatar', {
        'roomId': '!r:s',
        'bytes': Uint8List.fromList([1]),
        'name': 'a.png',
      });
      expect(r.ok, true);
    });

    test('rooms.create returns ok empty', () async {
      final r = await call('rooms.create', {'options': <String, dynamic>{}});
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('roomState.get returns empty content', () async {
      final r = await call('roomState.get', {
        'roomId': '!r:s',
        'eventType': 'm.room.name',
        'key': '',
      });
      expect(r.ok, true);
      expect(r.data?['content'], isEmpty);
    });

    test('roomState.set returns ok empty', () async {
      final r = await call('roomState.set', {
        'roomId': '!r:s',
        'eventType': 'm.room.name',
        'key': '',
        'content': {'name': 'x'},
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('roomState.canChange returns false', () async {
      final r = await call('roomState.canChange', {
        'roomId': '!r:s',
        'eventType': 'm.room.name',
      });
      expect(r.ok, true);
      expect(r.data?['canChange'], false);
    });

    test('roomState.getPowerLevel returns 0', () async {
      final r = await call('roomState.getPowerLevel', {
        'roomId': '!r:s',
        'userId': '@u:s',
      });
      expect(r.ok, true);
      expect(r.data?['powerLevel'], 0);
    });

    test('members.get returns empty list', () async {
      final r = await call('members.get', {'roomId': '!r:s'});
      expect(r.ok, true);
      expect(r.data?['members'], isEmpty);
    });

    test('members.getUser returns empty user map', () async {
      final r = await call('members.getUser', {
        'roomId': '!r:s',
        'userId': '@u:s',
      });
      expect(r.ok, true);
      expect(r.data?['user'], isEmpty);
    });

    test('members.search returns empty list', () async {
      final r = await call('members.search', {'term': 'ali'});
      expect(r.ok, true);
      expect(r.data?['users'], isEmpty);
    });

    test('unknown op still errors', () async {
      final r = await call('roomMgmt.bogus', {});
      expect(r.ok, false);
      expect(r.error?.code, 'unknown_op');
    });
  });

  group('WorkerBackend room mgmt + state + members via stub (round-trip)', () {
    late WorkerBackend backend;

    setUp(() => backend = WorkerBackend(handlerFactory: StubWorkerHandler.new));
    tearDown(() async {
      if (backend.isReady) await backend.disconnect();
    });

    test('void room mgmt ops complete without error', () async {
      await backend.connect();
      await expectLater(backend.leaveRoom('acct', '!r:s'), completes);
      await expectLater(backend.joinRoom('acct', '!r:s'), completes);
      await expectLater(
        backend.inviteUser('acct', '!r:s', '@u:s'),
        completes,
      );
      await expectLater(
        backend.kickUser('acct', '!r:s', '@u:s'),
        completes,
      );
      await expectLater(backend.banUser('acct', '!r:s', '@u:s'), completes);
      await expectLater(backend.unbanUser('acct', '!r:s', '@u:s'), completes);
    });

    test('setRoomName returns empty string through the transport', () async {
      await backend.connect();
      expect(await backend.setRoomName('acct', '!r:s', 'n'), '');
    });

    test('setRoomTopic returns empty string through the transport', () async {
      await backend.connect();
      expect(await backend.setRoomTopic('acct', '!r:s', 't'), '');
    });

    test('setRoomAvatar returns empty string through the transport', () async {
      await backend.connect();
      expect(
        await backend.setRoomAvatar(
          'acct',
          '!r:s',
          Uint8List.fromList([1]),
          'a.png',
        ),
        '',
      );
    });

    test('createRoom returns empty string through the transport', () async {
      await backend.connect();
      expect(await backend.createRoom('acct', {'name': 'room'}), '');
    });

    test('getRoomState returns empty map through the transport', () async {
      await backend.connect();
      expect(
        await backend.getRoomState('acct', '!r:s', 'm.room.name', ''),
        isEmpty,
      );
    });

    test('setRoomState returns empty string through the transport', () async {
      await backend.connect();
      expect(
        await backend.setRoomState('acct', '!r:s', 'm.room.name', '', {}),
        '',
      );
    });

    test('canChangeState returns false through the transport', () async {
      await backend.connect();
      expect(await backend.canChangeState('acct', '!r:s', 'm.room.name'), false);
    });

    test('getPowerLevel returns 0 through the transport', () async {
      await backend.connect();
      expect(await backend.getPowerLevel('acct', '!r:s', '@u:s'), 0);
    });

    test('getJoinedMembers returns empty list through the transport',
        () async {
      await backend.connect();
      expect(await backend.getJoinedMembers('acct', '!r:s'), isEmpty);
    });

    test('getUser returns a fallback UserDto through the transport', () async {
      await backend.connect();
      final user = await backend.getUser('acct', '!r:s', '@u:s');
      expect(user.userId, '@u:s');
    });

    test('searchUsers returns empty list through the transport', () async {
      await backend.connect();
      expect(await backend.searchUsers('acct', 'ali'), isEmpty);
    });
  });

  group('InProcessBackend room mgmt + state + members no-op stubs', () {
    late InProcessBackend backend;

    setUp(() => backend = InProcessBackend());
    tearDown(() => backend.disconnect());

    test('void room mgmt ops complete', () async {
      await backend.connect();
      await expectLater(backend.leaveRoom('a', '!r'), completes);
      await expectLater(backend.joinRoom('a', '!r'), completes);
      await expectLater(backend.inviteUser('a', '!r', '@u'), completes);
      await expectLater(backend.kickUser('a', '!r', '@u'), completes);
      await expectLater(backend.banUser('a', '!r', '@u'), completes);
      await expectLater(backend.unbanUser('a', '!r', '@u'), completes);
    });

    test('state setters return empty string', () async {
      await backend.connect();
      expect(await backend.setRoomName('a', '!r', 'n'), '');
      expect(await backend.setRoomTopic('a', '!r', 't'), '');
      expect(await backend.setRoomAvatar('a', '!r', Uint8List(0), 'f'), '');
      expect(await backend.createRoom('a', {}), '');
    });

    test('room state ops return neutral values', () async {
      await backend.connect();
      expect(await backend.getRoomState('a', '!r', 'm.room.name', ''), isEmpty);
      expect(await backend.setRoomState('a', '!r', 'm.room.name', '', {}), '');
      expect(await backend.canChangeState('a', '!r', 'm.room.name'), false);
      expect(await backend.getPowerLevel('a', '!r', '@u'), 0);
    });

    test('members ops return neutral values', () async {
      await backend.connect();
      expect(await backend.getJoinedMembers('a', '!r'), isEmpty);
      final user = await backend.getUser('a', '!r', '@u');
      expect(user.userId, '@u');
      expect(await backend.searchUsers('a', 'term'), isEmpty);
    });
  });
}

void _noopEmit(BackendEvent event) {}

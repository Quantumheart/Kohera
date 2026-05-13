import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

StrippedStateEvent _joinRulesEvent({
  required String joinRule,
  List<Map<String, Object?>>? allow,
}) {
  return StrippedStateEvent(
    type: EventTypes.RoomJoinRules,
    stateKey: '',
    senderId: '@admin:example.com',
    content: {
      'join_rule': joinRule,
      if (allow != null) 'allow': allow,
    },
  );
}

void _stubJoinRules(MockRoom room, StrippedStateEvent? event) {
  when(room.getState(EventTypes.RoomJoinRules)).thenReturn(event);
}

void _stubRoomVersion(MockRoom room, String? version) {
  when(room.roomVersion).thenReturn(version);
}

void main() {
  late MockClient client;
  late SpaceAccessService service;

  setUp(() {
    client = MockClient();
    service = SpaceAccessService(client: client);
  });

  group('getJoinMode', () {
    test('maps each join_rule string to JoinMode', () {
      final cases = {
        'public': JoinMode.public,
        'knock': JoinMode.knock,
        'invite': JoinMode.invite,
        'restricted': JoinMode.restricted,
        'knock_restricted': JoinMode.knockRestricted,
      };
      for (final entry in cases.entries) {
        final room = MockRoom();
        _stubJoinRules(room, _joinRulesEvent(joinRule: entry.key));
        expect(service.getJoinMode(room), entry.value,
            reason: 'join_rule=${entry.key}',);
      }
    });

    test('falls back to invite when state event missing', () {
      final room = MockRoom();
      _stubJoinRules(room, null);
      expect(service.getJoinMode(room), JoinMode.invite);
    });

    test('falls back to invite for unknown join_rule string', () {
      final room = MockRoom();
      _stubJoinRules(room, _joinRulesEvent(joinRule: 'private'));
      expect(service.getJoinMode(room), JoinMode.invite);
    });
  });

  group('allowedSpaceIds', () {
    test('returns room_ids from m.room_membership entries', () {
      final room = MockRoom();
      _stubJoinRules(
        room,
        _joinRulesEvent(joinRule: 'restricted', allow: [
          {'type': 'm.room_membership', 'room_id': '!a:example.com'},
          {'type': 'm.room_membership', 'room_id': '!b:example.com'},
        ],),
      );
      expect(
          service.allowedSpaceIds(room), ['!a:example.com', '!b:example.com'],);
    });

    test('filters out non-m.room_membership entries', () {
      final room = MockRoom();
      _stubJoinRules(
        room,
        _joinRulesEvent(joinRule: 'restricted', allow: [
          {'type': 'm.room_membership', 'room_id': '!a:example.com'},
          {'type': 'org.example.future', 'room_id': '!skip:example.com'},
        ],),
      );
      expect(service.allowedSpaceIds(room), ['!a:example.com']);
    });

    test('returns empty when state missing', () {
      final room = MockRoom();
      _stubJoinRules(room, null);
      expect(service.allowedSpaceIds(room), isEmpty);
    });

    test('returns empty when allow list missing', () {
      final room = MockRoom();
      _stubJoinRules(room, _joinRulesEvent(joinRule: 'invite'));
      expect(service.allowedSpaceIds(room), isEmpty);
    });

    test('skips entries with missing or non-string room_id', () {
      final room = MockRoom();
      _stubJoinRules(
        room,
        _joinRulesEvent(joinRule: 'restricted', allow: [
          {'type': 'm.room_membership'},
          {'type': 'm.room_membership', 'room_id': 42},
          {'type': 'm.room_membership', 'room_id': '!ok:example.com'},
        ],),
      );
      expect(service.allowedSpaceIds(room), ['!ok:example.com']);
    });
  });

  group('needsUpgradeForRestricted', () {
    test('v7 needs upgrade for restricted', () {
      final room = MockRoom();
      _stubRoomVersion(room, '7');
      expect(service.needsUpgradeForRestricted(room, wantKnock: false), isTrue);
    });

    test('v8 ok for restricted', () {
      final room = MockRoom();
      _stubRoomVersion(room, '8');
      expect(
          service.needsUpgradeForRestricted(room, wantKnock: false), isFalse,);
    });

    test('v9 needs upgrade for knock_restricted', () {
      final room = MockRoom();
      _stubRoomVersion(room, '9');
      expect(service.needsUpgradeForRestricted(room, wantKnock: true), isTrue);
    });

    test('v10 ok for knock_restricted', () {
      final room = MockRoom();
      _stubRoomVersion(room, '10');
      expect(service.needsUpgradeForRestricted(room, wantKnock: true), isFalse);
    });

    test('missing create event defaults to v1 (needs upgrade)', () {
      final room = MockRoom();
      _stubRoomVersion(room, null);
      expect(service.needsUpgradeForRestricted(room, wantKnock: false), isTrue);
    });

    test('non-numeric version treated as needs upgrade', () {
      final room = MockRoom();
      _stubRoomVersion(room, 'org.matrix.msc-future');
      expect(service.needsUpgradeForRestricted(room, wantKnock: false), isTrue);
    });
  });

  group('applyJoinMode', () {
    test('restricted writes correct payload', () async {
      final room = MockRoom();
      when(room.id).thenReturn('!r:e.com');
      final allow = MockRoom();
      when(allow.id).thenReturn('!s:e.com');
      when(client.getRoomById('!r:e.com')).thenReturn(null);
      when(
        client.setRoomStateWithKey(any, any, any, any),
      ).thenAnswer((_) async => 'evt');

      await service.setRestrictedJoin(room, [allow]);

      final captured = verify(
        client.setRoomStateWithKey(
          '!r:e.com',
          'm.room.join_rules',
          '',
          captureAny,
        ),
      ).captured.single as Map<String, Object?>;
      expect(captured['join_rule'], 'restricted');
      expect(captured['allow'], [
        {'type': 'm.room_membership', 'room_id': '!s:e.com'},
      ]);
    });

    test('knock_restricted writes correct join_rule', () async {
      final room = MockRoom();
      when(room.id).thenReturn('!r:e.com');
      final allow = MockRoom();
      when(allow.id).thenReturn('!s:e.com');
      when(client.getRoomById('!r:e.com')).thenReturn(null);
      when(
        client.setRoomStateWithKey(any, any, any, any),
      ).thenAnswer((_) async => 'evt');

      await service.setKnockRestricted(room, [allow]);

      final captured = verify(
        client.setRoomStateWithKey(any, any, any, captureAny),
      ).captured.single as Map<String, Object?>;
      expect(captured['join_rule'], 'knock_restricted');
    });

    test('invite writes no allow list', () async {
      final room = MockRoom();
      when(room.id).thenReturn('!r:e.com');
      when(client.getRoomById('!r:e.com')).thenReturn(null);
      when(
        client.setRoomStateWithKey(any, any, any, any),
      ).thenAnswer((_) async => 'evt');

      await service.setInviteOnly(room);

      final captured = verify(
        client.setRoomStateWithKey(any, any, any, captureAny),
      ).captured.single as Map<String, Object?>;
      expect(captured['join_rule'], 'invite');
      expect(captured.containsKey('allow'), isFalse);
    });

    test('preserves non-m.room_membership allow entries', () async {
      final room = MockRoom();
      when(room.id).thenReturn('!r:e.com');
      _stubJoinRules(
        room,
        _joinRulesEvent(
          joinRule: 'restricted',
          allow: [
            {'type': 'm.room_membership', 'room_id': '!old:e.com'},
            {'type': 'org.example.future', 'value': 'keep me'},
          ],
        ),
      );
      when(client.getRoomById('!r:e.com')).thenReturn(room);
      when(
        client.setRoomStateWithKey(any, any, any, any),
      ).thenAnswer((_) async => 'evt');

      final newAllow = MockRoom();
      when(newAllow.id).thenReturn('!new:e.com');
      await service.setRestrictedJoin(room, [newAllow]);

      final captured = verify(
        client.setRoomStateWithKey(any, any, any, captureAny),
      ).captured.single as Map<String, Object?>;
      final allow =
          (captured['allow']! as List).cast<Map<String, Object?>>();
      expect(
        allow.any(
          (e) =>
              e['type'] == 'org.example.future' && e['value'] == 'keep me',
        ),
        isTrue,
      );
      expect(
        allow.any(
          (e) =>
              e['type'] == 'm.room_membership' &&
              e['room_id'] == '!new:e.com',
        ),
        isTrue,
      );
      expect(
        allow.any(
          (e) =>
              e['type'] == 'm.room_membership' &&
              e['room_id'] == '!old:e.com',
        ),
        isFalse,
        reason: 'old m.room_membership entry should be replaced',
      );
    });

    test('empty allowSpaces for restricted throws', () {
      final room = MockRoom();
      when(room.id).thenReturn('!r:e.com');
      expect(
        () => service.setRestrictedJoin(room, []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty allowSpaces for knock_restricted throws', () {
      final room = MockRoom();
      when(room.id).thenReturn('!r:e.com');
      expect(
        () => service.setKnockRestricted(room, []),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('rewireParentSpaces', () {
    test('rewrites m.space.child on each parent space', () async {
      final parent = MockRoom();
      when(parent.isSpace).thenReturn(true);
      when(parent.spaceChildren).thenReturn([
        SpaceChild.fromState(
          StrippedStateEvent(
            type: EventTypes.SpaceChild,
            stateKey: '!old:e.com',
            senderId: '@a:e.com',
            content: {
              'via': ['e.com'],
            },
          ),
        ),
      ]);
      when(parent.setSpaceChild(any)).thenAnswer((_) async {});
      when(parent.removeSpaceChild(any)).thenAnswer((_) async {});

      final other = MockRoom();
      when(other.isSpace).thenReturn(false);
      when(other.spaceChildren).thenReturn([]);

      when(client.rooms).thenReturn([parent, other]);

      await service.rewireParentSpaces('!old:e.com', '!new:e.com');

      verify(parent.setSpaceChild('!new:e.com')).called(1);
      verify(parent.removeSpaceChild('!old:e.com')).called(1);
      verifyNever(other.setSpaceChild(any));
    });
  });

  group('serverSupportedRoomVersions', () {
    test('returns available versions from capabilities', () async {
      when(client.getCapabilities()).thenAnswer(
        (_) async => Capabilities.fromJson({
          'm.room_versions': {
            'default': '10',
            'available': {
              '1': 'stable',
              '9': 'stable',
              '10': 'stable',
            },
          },
        }),
      );

      final versions = await service.serverSupportedRoomVersions();
      expect(versions, containsAll(<String>['1', '9', '10']));
    });

    test('caches subsequent calls', () async {
      when(client.getCapabilities()).thenAnswer(
        (_) async => Capabilities.fromJson({
          'm.room_versions': {
            'default': '10',
            'available': {'10': 'stable'},
          },
        }),
      );

      await service.serverSupportedRoomVersions();
      await service.serverSupportedRoomVersions();
      verify(client.getCapabilities()).called(1);
    });

    test('returns empty on error', () async {
      when(client.getCapabilities()).thenThrow(Exception('network'));
      expect(await service.serverSupportedRoomVersions(), isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/call_constants.dart';
import 'package:kohera/data/repositories/call_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

class _FakeStrippedStateEvent extends Fake implements StrippedStateEvent {
  _FakeStrippedStateEvent({
    required this.senderId,
    required Map<String, dynamic> content,
  }) : _content = content;

  @override
  final String senderId;

  final Map<String, dynamic> _content;

  @override
  Map<String, dynamic> get content => _content;
}

void main() {
  late MockClient mockClient;
  late MockRoom mockRoom;
  late CallRepository repo;

  Map<String, dynamic> membershipContent() => {
        'application': 'm.call',
        'call_id': 'g1',
        'scope': 'm.room',
        'device_id': 'DEV2',
        'expires': 14400000,
        'foci_preferred': [
          {
            'type': 'livekit',
            'livekit_service_url': 'https://lk.example.com',
            'livekit_alias': 'alias',
          },
        ],
      };

  void stubMemberStates(Map<String, _FakeStrippedStateEvent> entries) {
    when(mockRoom.states).thenReturn(
      entries.isEmpty
          ? {}
          : {
              callMemberEventType: Map<String, StrippedStateEvent>.from(entries),
            },
    );
  }

  setUp(() {
    mockClient = MockClient();
    mockRoom = MockRoom();
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockClient.deviceID).thenReturn('MYDEVICE');
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    stubMemberStates({});
    repo = CallRepository(clientService: MatrixClientService(mockClient));
  });

  group('identity and state key', () {
    test('exposes user id, device id, and membership state key', () {
      expect(repo.userId, '@me:example.com');
      expect(repo.deviceId, 'MYDEVICE');
      expect(
        repo.membershipStateKey,
        '_@me:example.com_MYDEVICE_m.call',
      );
    });
  });

  group('membership queries', () {
    test('unknown room yields empty results', () {
      expect(repo.roomHasActiveCall('!unknown:example.com'), isFalse);
      expect(repo.activeCallIdsForRoom('!unknown:example.com'), isEmpty);
      expect(repo.callParticipantCount('!unknown:example.com', 'g1'), 0);
      expect(repo.selectOldestFocus('!unknown:example.com'), isNull);
    });

    test('roomHasActiveCall detects memberships', () {
      stubMemberStates({
        '_@other:example.com_DEV2_m.call': _FakeStrippedStateEvent(
          senderId: '@other:example.com',
          content: membershipContent(),
        ),
      });

      expect(repo.roomHasActiveCall('!room:example.com'), isTrue);
    });

    test('roomHasRemoteActiveCall ignores the local device', () {
      stubMemberStates({
        '_@me:example.com_MYDEVICE_m.call': _FakeStrippedStateEvent(
          senderId: '@me:example.com',
          content: membershipContent(),
        ),
      });

      expect(repo.roomHasRemoteActiveCall('!room:example.com'), isFalse);
      expect(repo.roomHasActiveCall('!room:example.com'), isTrue);
    });

    test('participant queries resolve user ids and call ids', () {
      stubMemberStates({
        '_@alice:example.com_DEV2_m.call': _FakeStrippedStateEvent(
          senderId: '@alice:example.com',
          content: membershipContent(),
        ),
        '_@bob:example.com_DEV3_m.call': _FakeStrippedStateEvent(
          senderId: '@bob:example.com',
          content: membershipContent(),
        ),
      });

      expect(
        repo.activeCallParticipantUserIds('!room:example.com'),
        {'@alice:example.com', '@bob:example.com'},
      );
      expect(repo.activeCallIdsForRoom('!room:example.com'), ['g1']);
      expect(repo.callParticipantCount('!room:example.com', 'g1'), 2);
    });

    test('selectOldestFocus resolves through the resolver', () {
      stubMemberStates({
        '_@alice:example.com_DEV2_m.call': _FakeStrippedStateEvent(
          senderId: '@alice:example.com',
          content: membershipContent(),
        ),
      });

      final focus = repo.selectOldestFocus('!room:example.com');
      expect(focus?.url, 'https://lk.example.com');
      expect(focus?.alias, 'alias');
    });
  });

  group('membership writes', () {
    test('joinCallMembership publishes this device state key', () async {
      when(
        mockClient.setRoomStateWithKey(any, any, any, any),
      ).thenAnswer((_) async => r'$evt');

      await repo.joinCallMembership(
        '!room:example.com',
        'alias',
        livekitServiceUrl: 'https://lk.example.com',
        isVideo: true,
      );

      final content = verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          callMemberEventType,
          '_@me:example.com_MYDEVICE_m.call',
          captureAny,
        ),
      ).captured.single as Map<String, dynamic>;
      expect(content['device_id'], 'MYDEVICE');
      expect(content[kIoKoheraIsVideo], isTrue);
      expect(content['application'], 'm.call');
    });

    test('leaveCallMembership clears the state', () async {
      when(
        mockClient.setRoomStateWithKey(any, any, any, any),
      ).thenAnswer((_) async => r'$evt');

      await repo.leaveCallMembership('!room:example.com');

      final content = verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          callMemberEventType,
          '_@me:example.com_MYDEVICE_m.call',
          captureAny,
        ),
      ).captured.single as Map<String, dynamic>;
      expect(content, isEmpty);
    });
  });

  group('wellknown', () {
    test('extracts the livekit service url', () async {
      when(mockClient.getWellknown()).thenAnswer(
        (_) async => DiscoveryInformation.fromJson({
          'm.homeserver': {'base_url': 'https://hs.example.com'},
          'org.matrix.msc4143.rtc_foci': [
            {'type': 'livekit', 'livekit_service_url': 'https://lk.example.com'},
          ],
        }),
      );

      expect(
        await repo.livekitServiceUrlFromWellknown(),
        'https://lk.example.com',
      );
    });

    test('returns null when no rtc foci are configured', () async {
      when(mockClient.getWellknown()).thenAnswer(
        (_) async => DiscoveryInformation.fromJson({
          'm.homeserver': {'base_url': 'https://hs.example.com'},
        }),
      );

      expect(await repo.livekitServiceUrlFromWellknown(), isNull);
    });
  });
}

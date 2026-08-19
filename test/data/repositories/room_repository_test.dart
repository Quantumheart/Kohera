import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_permissions.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;
  late RoomRepository repo;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.database).thenReturn(_FakeDatabase());
    service = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
    repo = RoomRepository(matrix: service);
  });

  group('summaryFor', () {
    test('returns null for unknown room', () {
      when(mockClient.getRoomById('!unknown:example.com')).thenReturn(null);
      expect(repo.summaryFor('!unknown:example.com'), isNull);
    });

    test('returns KoheraRoomSummary for known room', () {
      final room = MockRoom();
      when(room.id).thenReturn('!room:example.com');
      when(room.getLocalizedDisplayname()).thenReturn('Test Room');
      when(room.isSpace).thenReturn(false);
      when(room.membership).thenReturn(Membership.join);
      when(room.notificationCount).thenReturn(0);
      when(room.highlightCount).thenReturn(0);
      when(room.pinnedEventIds).thenReturn([]);
      when(room.typingUsers).thenReturn([]);
      when(room.lastEvent).thenReturn(null);
      when(room.isDirectChat).thenReturn(false);
      when(room.encrypted).thenReturn(false);
      when(room.isFavourite).thenReturn(false);
      when(room.spaceChildren).thenReturn([]);
      when(room.avatar).thenReturn(null);
      when(room.topic).thenReturn('');
      when(room.canonicalAlias).thenReturn('');
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(mockClient.userID).thenReturn('@me:example.com');

      final summary = repo.summaryFor('!room:example.com');

      expect(summary, isA<KoheraRoomSummary>());
      expect(summary!.roomId, '!room:example.com');
      expect(summary.displayname, 'Test Room');
    });
  });

  group('permissionsFor', () {
    test('returns null for unknown room', () {
      when(mockClient.getRoomById('!unknown:example.com')).thenReturn(null);
      expect(repo.permissionsFor('!unknown:example.com'), isNull);
    });

    test('returns KoheraRoomPermissions for known room', () {
      final room = MockRoom();
      when(room.id).thenReturn('!room:example.com');
      when(room.getLocalizedDisplayname()).thenReturn('Test Room');
      when(room.topic).thenReturn('');
      when(room.encrypted).thenReturn(false);
      when(room.canonicalAlias).thenReturn('');
      when(room.getParticipants()).thenReturn([]);
      when(room.canChangeStateEvent(any)).thenReturn(false);
      when(room.canChangeJoinRules).thenReturn(false);
      when(room.canChangePowerLevel).thenReturn(false);
      when(room.joinRules).thenReturn(null);
      when(room.getState(any)).thenReturn(null);
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(mockClient.userID).thenReturn('@me:example.com');

      final permissions = repo.permissionsFor('!room:example.com');

      expect(permissions, isA<KoheraRoomPermissions>());
      expect(permissions!.roomId, '!room:example.com');
    });
  });

  group('memberListFor', () {
    test('returns null for unknown room', () async {
      when(mockClient.getRoomById('!unknown:example.com')).thenReturn(null);
      expect(await repo.memberListFor('!unknown:example.com'), isNull);
    });
  });

  group('selection', () {
    test('selectSpace delegates to SelectionService', () {
      repo.selectSpace('!space:example.com');
      expect(repo.selectedSpaceIds, {'!space:example.com'});
    });

    test('selectRoom delegates to SelectionService', () {
      repo.selectRoom('!room:example.com');
      expect(repo.selectedRoomId, '!room:example.com');
    });

    test('clearSpaceSelection delegates to SelectionService', () {
      repo.selectSpace('!space:example.com');
      repo.clearSpaceSelection();
      expect(repo.selectedSpaceIds, isEmpty);
    });
  });

  group('roomSummaries', () {
    test('returns empty list when no rooms', () {
      when(mockClient.rooms).thenReturn([]);
      expect(repo.roomSummaries, isEmpty);
    });
  });

  group('spaceTree', () {
    test('returns empty list when no spaces', () {
      when(mockClient.rooms).thenReturn([]);
      expect(repo.spaceTree, isEmpty);
    });
  });

  group('notifyListeners', () {
    test('notifies on MatrixService change', () {
      var notified = false;
      repo.addListener(() => notified = true);

      service.notifyListeners();

      expect(notified, isTrue);
    });
  });

  group('updateMatrixService', () {
    test('swaps internal reference and still works', () {
      repo.selectSpace('!space:example.com');
      expect(repo.selectedSpaceIds, {'!space:example.com'});

      final service2 = MatrixService(
        client: mockClient,
        storage: mockStorage,
        clientName: 'test2',
      );
      repo.updateMatrixService(service2);

      repo.selectSpace('!other:example.com');
      expect(repo.selectedSpaceIds, {'!other:example.com'});
    });
  });

  group('setPushRuleState', () {
    test('calls room.setPushRuleState with SDK enum', () async {
      final room = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);

      await repo.setPushRuleState(
        '!room:example.com',
        KoheraPushRuleState.dontNotify,
      );

      verify(room.setPushRuleState(PushRuleState.dontNotify)).called(1);
    });
  });

  group('dispose', () {
    test('does not notify after dispose', () {
      var notified = false;
      repo.addListener(() => notified = true);

      repo.dispose();
      notified = false;
      service.notifyListeners();

      expect(notified, isFalse);
    });
  });
}

class _FakeDatabase extends Fake implements DatabaseApi {
  @override
  Future<Map<String, dynamic>?> getClient(String name) async => null;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async =>
      <Event>[];
}

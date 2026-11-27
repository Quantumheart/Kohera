import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/account_session.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_permissions.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
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
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.database).thenReturn(_FakeDatabase());
    service = MatrixService(
      accountSession: AccountSession(matrixClientService: MatrixClientService(mockClient)),
      storage: mockStorage,
      clientName: 'test',
    );
    repo = RoomRepository(clientService: service.matrixClientService);
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

  group('roomSummaries', () {
    test('returns empty list when no rooms', () {
      when(mockClient.rooms).thenReturn([]);
      expect(repo.roomSummaries, isEmpty);
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

  group('pin accessors', () {
    late MockRoom room;

    setUp(() {
      room = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(room.setPinnedEvents(any)).thenAnswer((_) async => '');
    });

    test('isPinned reflects room pinned events', () {
      when(room.pinnedEventIds).thenReturn([r'$pinned:s']);

      expect(repo.isPinned('!room:example.com', r'$pinned:s'), isTrue);
      expect(repo.isPinned('!room:example.com', r'$other:s'), isFalse);
    });

    test('isPinned returns false for unknown room', () {
      expect(repo.isPinned('!unknown:example.com', r'$e:s'), isFalse);
    });

    test('setPinned adds a new event', () async {
      when(room.pinnedEventIds).thenReturn([r'$a:s']);

      await repo.setPinned('!room:example.com', r'$b:s', true);

      verify(room.setPinnedEvents([r'$a:s', r'$b:s'])).called(1);
    });

    test('setPinned removes an event', () async {
      when(room.pinnedEventIds).thenReturn([r'$a:s', r'$b:s']);

      await repo.setPinned('!room:example.com', r'$a:s', false);

      verify(room.setPinnedEvents([r'$b:s'])).called(1);
    });

    test('setPinned does not duplicate an already pinned event', () async {
      when(room.pinnedEventIds).thenReturn([r'$a:s']);

      await repo.setPinned('!room:example.com', r'$a:s', true);

      verify(room.setPinnedEvents([r'$a:s'])).called(1);
    });
  });

  group('read markers and receipts', () {
    late MockRoom room;

    setUp(() {
      room = MockRoom();
      when(room.id).thenReturn('!room:example.com');
      when(room.receiptState).thenReturn(LatestReceiptState.empty());
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
    });

    test('readReceipts returns empty for unknown room', () {
      expect(repo.readReceipts('!unknown:example.com'), isEmpty);
    });

    test('readReceipts returns empty map when no receipts exist', () {
      when(mockClient.userID).thenReturn('@me:example.com');

      expect(repo.readReceipts('!room:example.com'), isEmpty);
    });

    test('latestOwnThreadReceiptTs returns 0 without a receipt', () {
      expect(
        repo.latestOwnThreadReceiptTs('!room:example.com', r'\$root:s'),
        0,
      );
    });

    test('fullyReadMarkerId returns null for unknown room', () {
      expect(repo.fullyReadMarkerId('!unknown:example.com'), isNull);
    });

    test('fullyReadMarkerId returns marker when set', () {
      when(room.fullyRead).thenReturn(r'\$read:s');

      expect(repo.fullyReadMarkerId('!room:example.com'), r'\$read:s');
    });

    test('fullyReadMarkerId returns null when empty', () {
      when(room.fullyRead).thenReturn('');

      expect(repo.fullyReadMarkerId('!room:example.com'), isNull);
    });

    test('notificationCount delegates to the room', () {
      when(room.notificationCount).thenReturn(3);

      expect(repo.notificationCount('!room:example.com'), 3);
      expect(repo.notificationCount('!unknown:example.com'), 0);
    });

    test('markRead sets the read marker and posts a private receipt',
        () async {
      await repo.markRead('!room:example.com', r'\$evt:s');

      verify(room.setReadMarker(r'\$evt:s')).called(1);
      verify(
        mockClient.postReceipt(
          '!room:example.com',
          ReceiptType.mRead,
          r'\$evt:s',
          threadId: 'main',
        ),
      ).called(1);
    });

    test('markRead posts a public receipt when requested', () async {
      await repo.markRead(
        '!room:example.com',
        r'\$evt:s',
        sendPublicReceipt: true,
      );

      verify(room.setReadMarker(r'\$evt:s', mRead: r'\$evt:s')).called(1);
    });

    test('powerLevelOf returns 0 for unknown room', () {
      expect(repo.powerLevelOf('!unknown:example.com', '@a:s'), 0);
    });

    test('powerLevelOf delegates to the room', () {
      when(room.getPowerLevelByUserId('@alice:example.com'))
          .thenReturn(PowerLevel(50));

      expect(repo.powerLevelOf('!room:example.com', '@alice:example.com'), 50);
    });

    test('member count accessors delegate to the room', () async {
      when(room.summary).thenReturn(
        RoomSummary.fromJson({'m.joined_member_count': 7}),
      );
      when(room.participantListComplete).thenReturn(true);
      when(mockClient.getJoinedMembersByRoom('!room:example.com'))
          .thenAnswer((_) async => {'@a:s': RoomMember.fromJson({})});

      expect(repo.joinedMemberCountOf('!room:example.com'), 7);
      expect(repo.participantListComplete('!room:example.com'), isTrue);
      expect(
        await repo.joinedMemberCountFromServer('!room:example.com'),
        1,
      );
      expect(repo.joinedMemberCountOf('!unknown:example.com'), 0);
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

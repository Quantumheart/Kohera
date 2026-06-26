import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/room_list_builder.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'room_list_unjoined_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockSpace;
  late MockRoom mockJoinedRoom;
  late FakeSpaceDiscoveryDataSource dataSource;
  late SpaceRoomsController controller;
  late SelectionService selection;
  late PreferencesService prefs;

  const spaceId = '!fake-space-0:example.org';
  const joinedRoomId = '!fake-room-lounge:example.org';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockSpace = MockRoom();
    mockJoinedRoom = MockRoom();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.userID).thenReturn('@me:example.com');

    // Space room setup
    when(mockSpace.id).thenReturn(spaceId);
    when(mockSpace.isSpace).thenReturn(true);
    when(mockSpace.membership).thenReturn(Membership.join);
    when(mockSpace.getLocalizedDisplayname()).thenReturn('Quantum HQ');
    when(mockSpace.avatar).thenReturn(null);
    when(mockSpace.canonicalAlias).thenReturn('#quantum-hq:example.org');
    // Space child for the joined room
    when(mockSpace.spaceChildren).thenReturn(
      [
        SpaceChild.fromState(
          StrippedStateEvent(
            type: EventTypes.SpaceChild,
            content: {'via': []},
            senderId: '@admin:example.org',
            stateKey: joinedRoomId,
          ),
        ),
      ],
    );
    when(mockSpace.topic).thenReturn('');
    when(mockSpace.client).thenReturn(mockClient);
    when(mockSpace.notificationCount).thenReturn(0);

    // Joined room setup
    when(mockJoinedRoom.id).thenReturn(joinedRoomId);
    when(mockJoinedRoom.isSpace).thenReturn(false);
    when(mockJoinedRoom.membership).thenReturn(Membership.join);
    when(mockJoinedRoom.getLocalizedDisplayname()).thenReturn('lounge');
    when(mockJoinedRoom.avatar).thenReturn(null);
    when(mockJoinedRoom.canonicalAlias).thenReturn('#lounge:example.org');
    when(mockJoinedRoom.directChatMatrixID).thenReturn(null);
    when(mockJoinedRoom.notificationCount).thenReturn(0);
    when(mockJoinedRoom.highlightCount).thenReturn(0);
    when(mockJoinedRoom.lastEvent).thenReturn(null);
    when(mockJoinedRoom.spaceChildren).thenReturn([]);
    when(mockJoinedRoom.topic).thenReturn('');
    when(mockJoinedRoom.client).thenReturn(mockClient);

    // Client rooms: space + joined room
    when(mockClient.rooms).thenReturn([mockSpace, mockJoinedRoom]);
    when(mockClient.getRoomById(spaceId)).thenReturn(mockSpace);
    when(mockClient.getRoomById(joinedRoomId)).thenReturn(mockJoinedRoom);

    selection = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selection);

    dataSource = FakeSpaceDiscoveryDataSource(delay: Duration.zero);
    // Mark the joined room and space as joined in the fake so they
    // don't appear in the unjoined list.
    unawaited(dataSource.joinRoom(spaceId));
    unawaited(dataSource.joinRoom(joinedRoomId));

    controller = SpaceRoomsController(
      dataSource: dataSource,
      client: mockClient,
    );
  });

  group('buildSectionItems — unjoined group', () {
    test('appends unjoined room items after joined rooms', () async {
      selection.selectSpace(spaceId);
      await controller.fetchSpaceRooms(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      expect(items.any((i) => i is HeaderItem), isTrue);
      expect(items.any((i) => i is RoomItem), isTrue);
      expect(items.any((i) => i is UnjoinedRoomGroupHeaderItem), isTrue);
      expect(items.any((i) => i is UnjoinedRoomItem), isTrue);
      expect(items.any((i) => i is SubspaceOpenItem), isTrue);
    });

    test('shows loading item when hierarchy is not cached', () {
      selection.selectSpace(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      expect(items.any((i) => i is UnjoinedRoomLoadingItem), isTrue);
      expect(items.any((i) => i is UnjoinedRoomGroupHeaderItem), isFalse);
    });

    test('shows error item on hierarchy failure', () async {
      selection.selectSpace(spaceId);
      controller = SpaceRoomsController(
        dataSource: FakeSpaceDiscoveryDataSource(
          delay: Duration.zero,
          failHierarchyForRoomId: spaceId,
        ),
        client: mockClient,
      );
      await controller.fetchSpaceRooms(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      expect(items.any((i) => i is UnjoinedRoomErrorItem), isTrue);
      expect(items.any((i) => i is UnjoinedRoomGroupHeaderItem), isFalse);
    });

    test('shows forbidden item on M_FORBIDDEN', () async {
      selection.selectSpace(spaceId);
      controller = SpaceRoomsController(
        dataSource: FakeSpaceDiscoveryDataSource(
          delay: Duration.zero,
          forbiddenHierarchyForRoomId: spaceId,
        ),
        client: mockClient,
      );
      await controller.fetchSpaceRooms(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      expect(items.any((i) => i is UnjoinedRoomForbiddenItem), isTrue);
    });

    test('hides unjoined group when section is collapsed', () async {
      selection.selectSpace(spaceId);
      await controller.fetchSpaceRooms(spaceId);

      await prefs.toggleSectionCollapsed(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      expect(items.any((i) => i is UnjoinedRoomGroupHeaderItem), isFalse);
      expect(items.any((i) => i is UnjoinedRoomItem), isFalse);
    });

    test('filters unjoined rooms by search query', () async {
      selection.selectSpace(spaceId);
      await controller.fetchSpaceRooms(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        'offtopic',
        spaceRoomsController: controller,
      );

      final unjoinedItems = items.whereType<UnjoinedRoomItem>().toList();
      expect(unjoinedItems, hasLength(1));
      expect(unjoinedItems.first.metadata.name, 'offtopic');
    });
  });

  group('_UnjoinedRoomTile join flow', () {
    test('controller.join removes room from unjoined list', () async {
      selection.selectSpace(spaceId);
      await controller.fetchSpaceRooms(spaceId);

      final state = controller.getRoomState(spaceId);
      expect(state.unjoinedRooms, isNotEmpty);

      final targetRoom = state.unjoinedRooms.first;

      await controller.join(
        roomId: targetRoom.roomId,
        parentSpaceId: spaceId,
      );

      // After join + refresh, the room should no longer be unjoined
      // (the fake marks it as joined).
      final updated = controller.getRoomState(spaceId);
      expect(
        updated.unjoinedRooms.any((r) => r.roomId == targetRoom.roomId),
        isFalse,
      );
    });
  });
}

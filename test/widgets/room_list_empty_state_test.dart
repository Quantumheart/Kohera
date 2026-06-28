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
import 'room_list_empty_state_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockSpace;
  late FakeSpaceDiscoveryDataSource dataSource;
  late SpaceRoomsController controller;
  late SelectionService selection;
  late PreferencesService prefs;

  const spaceId = '!fake-space-0:example.org';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockSpace = MockRoom();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.userID).thenReturn('@me:example.com');

    // Space room setup — joined but with NO joined child rooms.
    when(mockSpace.id).thenReturn(spaceId);
    when(mockSpace.isSpace).thenReturn(true);
    when(mockSpace.membership).thenReturn(Membership.join);
    when(mockSpace.getLocalizedDisplayname()).thenReturn('Quantum HQ');
    when(mockSpace.avatar).thenReturn(null);
    when(mockSpace.canonicalAlias).thenReturn('#quantum-hq:example.org');
    when(mockSpace.spaceChildren).thenReturn([
      // Space has children in the hierarchy, but the user has joined none.
      SpaceChild.fromState(
        StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {'via': []},
          senderId: '@admin:example.org',
          stateKey: '!fake-room-lounge:example.org',
        ),
      ),
    ]);
    when(mockSpace.topic).thenReturn('');
    when(mockSpace.client).thenReturn(mockClient);
    when(mockSpace.notificationCount).thenReturn(0);

    // Client knows only about the space — no joined child rooms.
    when(mockClient.rooms).thenReturn([mockSpace]);
    when(mockClient.getRoomById(spaceId)).thenReturn(mockSpace);

    selection = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selection);

    dataSource = FakeSpaceDiscoveryDataSource(delay: Duration.zero);
    // Mark the space as joined in the fake so it doesn't appear in unjoined.
    unawaited(dataSource.joinRoom(spaceId));

    controller = SpaceRoomsController(
      dataSource: dataSource,
      client: mockClient,
    );
  });

  group('zero-joined space empty state', () {
    test('section is skipped when hierarchy is not yet cached', () {
      selection.selectSpace(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      // When not cached, _hasMatchingUnjoined returns false and the
      // section is skipped entirely.  The loading UI is handled by
      // _SpaceEmptyState in the RoomList widget, not buildSectionItems.
      expect(items.any((i) => i is HeaderItem), isFalse);
      expect(items, isEmpty);
    });

    test('unjoined rooms appear after hierarchy fetch', () async {
      selection.selectSpace(spaceId);
      await controller.fetchSpaceRooms(spaceId);

      final items = buildSectionItems(
        selection,
        prefs,
        '',
        spaceRoomsController: controller,
      );

      // With zero joined rooms, the section still renders and shows
      // the unjoined group (header + tiles).
      expect(items.any((i) => i is HeaderItem), isTrue);
      expect(items.any((i) => i is UnjoinedRoomGroupHeaderItem), isTrue);
      expect(items.any((i) => i is UnjoinedRoomItem), isTrue);
    });

    test('error item shown on hierarchy failure', () async {
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
    });

    test('forbidden item shown on M_FORBIDDEN', () async {
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

    test(
      'controller reports unjoined rooms after fetch for zero-joined space',
      () async {
        selection.selectSpace(spaceId);
        await controller.fetchSpaceRooms(spaceId);

        final state = controller.getRoomState(spaceId);
        expect(state.loading, isFalse);
        expect(state.error, isNull);
        expect(state.previewForbidden, isFalse);
        expect(state.unjoinedRooms, isNotEmpty);
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>()])
import 'space_rooms_controller_test.mocks.dart';

void main() {
  late SpaceRoomsController controller;
  late FakeSpaceDiscoveryDataSource dataSource;
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);

    dataSource = FakeSpaceDiscoveryDataSource();

    controller = SpaceRoomsController(
      dataSource: dataSource,
      client: mockClient,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('SpaceRoomsController', () {
    group('getRoomState', () {
      test('initial state is empty', () {
        expect(controller.getRoomState('!any-space').unjoinedRooms, isEmpty);
        expect(controller.getRoomState('!any-space').subspaces, isEmpty);
      });
    });

    group('fetchSpaceRooms', () {
      test('updates state to success on valid fetch', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);

        expect(state.loading, false);
        expect(state.error, isNull);
        expect(state.previewForbidden, false);

        // Check that we got some rooms from the fake data
        expect(state.unjoinedRooms, isNotEmpty);
        expect(state.subspaces, isNotEmpty);

        // Verify the first unjoined room has expected properties
        final firstRoom = state.unjoinedRooms.first;
        expect(firstRoom.roomId, isNotEmpty);
        expect(firstRoom.name, isNotEmpty);
        expect(firstRoom.memberCount, greaterThan(0));
        expect(firstRoom.roomType, isNotEmpty);
      });

      test('excludes parent space and joined rooms', () async {
        const parentId = '!fake-space-0:example.org';

        final stateBefore = controller.getRoomState(parentId);
        expect(stateBefore.unjoinedRooms, isEmpty); // Not fetched yet

        await controller.fetchSpaceRooms(parentId);

        final stateAfter = controller.getRoomState(parentId);
        // The parent space should not appear in unjoined rooms
        expect(
          stateAfter.unjoinedRooms.every((room) => room.roomId != parentId),
          true,
        );
        // Rooms with type 'm.space' should not appear in unjoined rooms (they go to subspaces)
        expect(
          stateAfter.unjoinedRooms.every((room) => room.roomType != 'm.space'),
          true,
        );
      });

      test('separates rooms and subspaces correctly', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);

        // Both lists should have items from the fake data
        expect(state.unjoinedRooms, isNotEmpty);
        expect(state.subspaces, isNotEmpty);

        // Verify room types are correctly categorized
        expect(
          state.unjoinedRooms.every((room) => room.roomType != 'm.space'),
          true,
        );
        expect(
          state.subspaces.every((space) => space.roomType == 'm.space'),
          true,
        );
      });
    });

    group('join', () {
      test('calls joinRoom and returns joined ID', () async {
        const roomId = '!fake-room-lounge:example.org';
        const parentId = '!fake-space-0:example.org';

        final joinedId = await controller.join(
          roomId: roomId,
          parentSpaceId: parentId,
        );

        expect(joinedId, equals(roomId));
      });
    });
  });
}

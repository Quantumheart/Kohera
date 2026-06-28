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
  late SpaceDiscoveryDataSource dataSource;
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);

    dataSource = FakeSpaceDiscoveryDataSource(delay: Duration.zero);

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
        expect(controller.getRoomState('!any-space').loading, isFalse);
        expect(controller.getRoomState('!any-space').error, isNull);
        expect(
          controller.getRoomState('!any-space').previewForbidden,
          isFalse,
        );
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

        // Quantum HQ has 4 non-space children + 1 subspace, none joined.
        expect(state.unjoinedRooms, hasLength(4));
        expect(state.subspaces, hasLength(1));
      });

      test('excludes parent space from unjoined and subspace lists',
          () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);
        expect(
          state.unjoinedRooms.every((room) => room.roomId != parentId),
          true,
        );
        expect(
          state.subspaces.every((room) => room.roomId != parentId),
          true,
        );
      });

      test('separates rooms and subspaces by room type', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);
        expect(
          state.unjoinedRooms.every((room) => room.roomType != 'm.space'),
          true,
        );
        expect(
          state.subspaces.every((space) => space.roomType == 'm.space'),
          true,
        );
      });

      test('populates isSuggested from childrenState', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);

        // lounge and dev-talk are suggested; offtopic and announcements are not.
        final lounge = state.unjoinedRooms.firstWhere(
          (r) => r.roomId == '!fake-room-lounge:example.org',
        );
        final devtalk = state.unjoinedRooms.firstWhere(
          (r) => r.roomId == '!fake-room-devtalk:example.org',
        );
        final offtopic = state.unjoinedRooms.firstWhere(
          (r) => r.roomId == '!fake-room-offtopic:example.org',
        );
        final announcements = state.unjoinedRooms.firstWhere(
          (r) => r.roomId == '!fake-room-announcements:example.org',
        );

        expect(lounge.isSuggested, true);
        expect(devtalk.isSuggested, true);
        expect(offtopic.isSuggested, false);
        expect(announcements.isSuggested, false);
      });

      test('populates canonicalAlias and viaServers from hierarchy', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);

        final lounge = state.unjoinedRooms.firstWhere(
          (r) => r.roomId == '!fake-room-lounge:example.org',
        );
        expect(lounge.canonicalAlias, '#lounge:example.org');
      });

      test('sorts suggested-first then by m.space.child order', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);

        final state = controller.getRoomState(parentId);

        // Suggested rooms: lounge (order='a'), dev-talk (order='c')
        // Non-suggested rooms: offtopic (order='b'), announcements (order='d')
        // Expected order: lounge, dev-talk, offtopic, announcements
        expect(state.unjoinedRooms.map((r) => r.roomId).toList(), [
          '!fake-room-lounge:example.org',
          '!fake-room-devtalk:example.org',
          '!fake-room-offtopic:example.org',
          '!fake-room-announcements:example.org',
        ]);
      });

      test('transitions to error state on network failure', () async {
        const brokenId = '!fake-broken:example.org';

        await controller.fetchSpaceRooms(brokenId);

        final state = controller.getRoomState(brokenId);
        expect(state.loading, false);
        expect(state.error, isNotNull);
        expect(state.previewForbidden, false);
        expect(state.unjoinedRooms, isEmpty);
      });

      test('transitions to forbidden state on M_FORBIDDEN', () async {
        const forbiddenId = '!fake-forbidden:example.org';

        dataSource = FakeSpaceDiscoveryDataSource(
          delay: Duration.zero,
          forbiddenHierarchyForRoomId: forbiddenId,
        );
        controller = SpaceRoomsController(
          dataSource: dataSource,
          client: mockClient,
        );

        await controller.fetchSpaceRooms(forbiddenId);

        final state = controller.getRoomState(forbiddenId);
        expect(state.loading, false);
        expect(state.error, isNull);
        expect(state.previewForbidden, true);
        expect(state.unjoinedRooms, isEmpty);
      });

      test('caches results and does not re-fetch while loading', () async {
        const parentId = '!fake-space-0:example.org';

        // Start a fetch.
        final future = controller.fetchSpaceRooms(parentId);
        // Immediately start a second fetch — should be a no-op.
        await controller.fetchSpaceRooms(parentId);
        await future;

        final state = controller.getRoomState(parentId);
        expect(state.unjoinedRooms, isNotEmpty);
      });
    });

    group('refresh', () {
      test('re-fetches and updates cache', () async {
        const parentId = '!fake-space-0:example.org';

        await controller.fetchSpaceRooms(parentId);
        final stateBefore = controller.getRoomState(parentId);
        expect(stateBefore.unjoinedRooms, hasLength(4));

        // Join a room, then refresh — it should drop from unjoined.
        await dataSource.joinRoom('!fake-room-lounge:example.org');
        await controller.refresh(parentId);

        final stateAfter = controller.getRoomState(parentId);
        expect(stateAfter.unjoinedRooms, hasLength(3));
        expect(
          stateAfter.unjoinedRooms
              .every((r) => r.roomId != '!fake-room-lounge:example.org'),
          true,
        );
      });
    });

    group('join', () {
      test('delegates to dataSource.joinRoom and returns joined ID', () async {
        const roomId = '!fake-room-lounge:example.org';
        const parentId = '!fake-space-0:example.org';

        final joinedId = await controller.join(
          roomId: roomId,
          parentSpaceId: parentId,
        );

        expect(joinedId, equals(roomId));
      });

      test('derives via from alias when via not provided', () async {
        const roomId = '!fake-room-lounge:example.org';
        const alias = '#lounge:example.org';
        const parentId = '!fake-space-0:example.org';

        final joinedId = await controller.join(
          roomId: roomId,
          alias: alias,
          parentSpaceId: parentId,
        );

        expect(joinedId, equals(roomId));
        // The fake marks the room as joined.
        expect(dataSource.isMember(roomId), true);
      });

      test('refreshes parent space after successful join', () async {
        const roomId = '!fake-room-lounge:example.org';
        const parentId = '!fake-space-0:example.org';

        // Pre-fetch so the cache is populated.
        await controller.fetchSpaceRooms(parentId);
        expect(
          controller.getRoomState(parentId).unjoinedRooms,
          hasLength(4),
        );

        // Join the room — it should be removed from unjoined after refresh.
        await controller.join(
          roomId: roomId,
          parentSpaceId: parentId,
        );

        final state = controller.getRoomState(parentId);
        expect(state.unjoinedRooms, hasLength(3));
        expect(
          state.unjoinedRooms.every((r) => r.roomId != roomId),
          true,
        );
      });

      test('returns joined ID even when parent refresh fails', () async {
        dataSource = FakeSpaceDiscoveryDataSource(
          delay: Duration.zero,
          failHierarchyForRoomId: null,
        );
        controller = SpaceRoomsController(
          dataSource: dataSource,
          client: mockClient,
        );

        // joinRoom succeeds, but the refresh of the broken parent fails.
        // join still returns the joined ID.
        final joinedId = await controller.join(
          roomId: '!fake-room-lounge:example.org',
          parentSpaceId: '!fake-broken:example.org',
        );

        expect(joinedId, isNotNull);
      });

      test('returns null when joinRoom throws', () async {
        dataSource = _ThrowingJoinDataSource();
        controller = SpaceRoomsController(
          dataSource: dataSource,
          client: mockClient,
        );

        final joinedId = await controller.join(
          roomId: '!fake-room-lounge:example.org',
          parentSpaceId: '!fake-space-0:example.org',
        );

        expect(joinedId, isNull);
      });
    });
  });
}

/// A fake data source whose joinRoom always throws.
class _ThrowingJoinDataSource implements SpaceDiscoveryDataSource {
  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  }) async {
    return GetSpaceHierarchyResponse(rooms: []);
  }

  @override
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via}) async {
    throw Exception('Join failed');
  }

  @override
  bool isMember(String roomId) => false;

  @override
  bool isSpace(String roomId) => false;
}

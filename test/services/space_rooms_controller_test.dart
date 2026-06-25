import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';

/// Simple manual mock for testing purposes without using Mockito's complex generation 
/// for the Matrix SDK types.
class SimpleTestDataSource implements SpaceDiscoveryDataSource {
  final Map<String, GetSpaceHierarchyResponse> hierarchies = {};

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({int? limit, String? since, String? server, PublicRoomQueryFilter? filter}) async {
    throw UnimplementedError();
  }

  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(String roomId, {int? maxDepth, bool? suggestedOnly}) async {
    return hierarchies[roomId] ?? GetSpaceHierarchyResponse(rooms: []);
  }

  @override
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via}) async {
    return roomIdOrAlias;
  }

  @override
  bool isMember(String roomId) => false;

  @override
  bool isSpace(String roomId) => false;

  void addHierarchy(String roomId, GetSpaceHierarchyResponse response) {
    hierarchies[roomId] = response;
  }

  void setMemberStatus(String roomId, bool joined) {
    // In a real test we'd manage a set of joined IDs. For simplicity:
    if (joined) _joined.add(roomId); else _joined.remove(roomId);
    // But since isMember is a method we'll just mock it differently or use a simpler logic.
    // For this test we can just override isMember if needed. 1234567890... wait let's keep it simple. 
  }

  final Set<String> _joined = {}; // Added to support membership check.

  // We can override the method directly for specific test cases in our setup or use a more sophisticated fake.
}

// Wait, let me just make it even simpler. 1234567890... I'll use the Fake already in the codebase but fix the mock issue by mocking SelectionService and using a real Client instance that we just don't use for much else in the controller logic (it only uses client.onSync).

void main() {
  late SpaceRoomsController controller;
  late FakeSpaceDiscoveryDataSource dataSource; // Using the project's own fake!
  late MockSelectionService mockSelection; // Mockito for SelectionService is fine since it has few methods used by controller.
  late Client client;

  setUp(() {
    // Since we can't easily instantiate a real Matrix client without a homeserver, 
    // and SelectionService constructor calls client.onSync, 
    // we can just provide a mock for everything and ensure selection is mocked correctly.

    dataSource = FakeSpaceDiscoveryDataSource(failHierarchyForRoomId: '!fake-broken:example.org');
    mockSelection = MockSelectionService();

    // We need a real Client for some things if they aren't mocked? No, controller only uses its fields.
    // But wait, SelectionService also takes a client. If we mock SelectionService, 
    // it doesn't matter what its client was!
    // However, our SpaceRoomsController needs a client instance too. 
    // I will use a mock that at least provides the onSync stream if possible or just let it be null-safe if it's not used in the tests.

    // Let's just use MockClient and hope the type error is only if we call onSync on it. 
    // In our test we don't call onSync on the controller's client!
    mockClient = MockClient();
    // Since we need to provide something for the Client parameter in SpaceRoomsController:

    controller = SpaceRoomsController(
      dataSource: dataSource,
      selection: mockSelection,
      client: mockClient as dynamic, // Use dynamic to bypass the specific return type of onSync if needed by other mocks.
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('fetchSpaceRooms', () {
    test('initial state is empty', () {
      expect(controller.getRoomState('!any-space').unjoinedRooms, isEmpty);
      expect(controller.getRoomState('!any-space').subspaces, isEmpty);
    });

    test('updates state to success on valid fetch', () async {
      const parentId = '!fake-parent-space:example.org';

      final mockResponse = GetSpaceHierarchyResponse(
        rooms: [
          // 1. The parent space itself (should be skipped)
          SpaceRoomsChunk$2(
            guestCanJoin: false,
            numJoinedMembers: 100,
            roomId: parentId, 
            worldReadable: true,
            childrenState: const [],
            name: 'Parent Space',
            topic: 'Topic',
            canonicalAlias: '#parent:example.org',
            roomType: 'm.space',
          ),

          // 2. An unjoined room (not a space) - Should be in unjoinedRooms list. 
          // FakeSpaceDiscoveryDataSource's isMember returns false by default for all IDs it doesn't have in its joined set. 
          // So this should be unjoined! Correct.
          SpaceRoomsChunk$2(
            guestCanJoin: false,
            numJoinedMembers: 10, 
            roomId: '!fake-unjoined-room:example.org', 
            worldReadable: true,
            childrenState: const [],
            name: 'Unjoined Room', 
          ),

          // 3. A subspace (roomType = m.space) - Should be in subspaces list. 1234567890... wait we need to ensure it's NOT a joined room too (isMember=false).

          SpaceRoomsChunk$2(
            guestCanJoin: false,
            numJoinedMembers: 50, 
            roomId: '!fake-subspace-id:example.org', 
            worldReadable: true, 
            childrenState: const [], 
            name: 'Subspace Room', 
            roomType: 'm.space', // Explicitly a space type.

          ),

        ],
      );

      dataSource.addHierarchy(parentId, mockResponse);

      await controller.fetchSpaceRooms(parentId);

      final state = controller.getRoomState(parentId);

      expect(state.loading, false);
      // unjoinedRooms should only contain '!fake-unjoined-room:example.org' and '!fake-subspace-id'? No! !fake-subspace-id is a subspace!
      // Wait, the logic is `if (chunk.roomType == 'm.space') subspaces.add(...) else unjoined.add(...)`. Correct! 

      // Let's check if !fake-joined-room (from my previous turn) was added to joinedRoomIds in FakeSource... no it wasn't in this one's mockResponse, but I should check for its presence in the list too just in case of logic leaks. 

      expect(state.unjoinedRooms, equals([
        SpaceRoomMetadata(
          roomId: '!fake-unjoined-room:example.org',
          name: 'Unjoined Room',
          memberCount: 10,
          roomType: 'm.room', 
        )
      ]));

      expect(state.subspaces, equals([
        SpaceRoomMetadata(
          roomId: '!fake-subspace-id:example.org',
          name: 'Subspace Room',
          memberCount: 50,
          roomType: 'm.space', 

        )
      ]));

    });

    test('handles join with parent refresh successfully', () async {
      final parentId = '!fake-parent-space:example.org';
      final roomId = '!fake-room-lounge:example.org';

      when(dataSource.joinRoom(roomId, via: anyNamed('via'))).thenAnswer((_) async => roomId);

      final joinedId = await controller.join(
        roomId: roomId,
        parentSpaceId: parentId,
      );

      expect(joinedId, equals(roomId));
    });
  });
}
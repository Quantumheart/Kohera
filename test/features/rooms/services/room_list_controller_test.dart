// Tests pass redundant args to mockito stubs for explicitness.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/services/room_list_controller.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'room_list_controller_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<SelectionService>(),
  MockSpec<PreferencesService>(),
  MockSpec<SpaceRoomsController>(),
  MockSpec<RoomListSearchController>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
])
void main() {
  late MockMatrixService matrix;
  late MockSelectionService selection;
  late MockPreferencesService prefs;
  late MockSpaceRoomsController spaceRooms;
  late MockRoomListSearchController messageSearch;
  late MockClient client;

  RoomListController makeController() => RoomListController(
    matrixService: matrix,
    selectionService: selection,
    preferencesService: prefs,
    spaceRoomsController: spaceRooms,
    messageSearchController: messageSearch,
  );

  KoheraRoomSummary summary({String roomId = '!r:example.com'}) =>
      KoheraRoomSummary(
        roomId: roomId,
        displayname: 'Room $roomId',
        isDirectChat: false,
        isEncrypted: false,
        isSpace: false,
        notificationCount: 0,
        highlightCount: 0,
        typingDisplayNames: const [],
        pinnedEventIds: const [],
        spaceChildCount: 0,
        isFavourite: false,
        lastEventPreview: '',
        lastEventIsThreadReply: false,
      );

  setUp(() {
    matrix = MockMatrixService();
    selection = MockSelectionService();
    prefs = MockPreferencesService();
    spaceRooms = MockSpaceRoomsController();
    messageSearch = MockRoomListSearchController();
    client = MockClient();

    when(matrix.client).thenReturn(client);
    when(selection.selectedSpaceIds).thenReturn({});
    when(selection.rooms).thenReturn([]);
    when(selection.spaceTree).thenReturn([]);
    when(selection.spaces).thenReturn([]);
    when(selection.invitedRooms).thenReturn([]);
    when(selection.orphanRooms).thenReturn([]);
    when(prefs.collapsedSpaceSections).thenReturn({});
    when(messageSearch.results).thenReturn([]);
    when(messageSearch.isLoading).thenReturn(false);
    when(messageSearch.nextBatch).thenReturn(null);
    when(messageSearch.totalCount).thenReturn(null);
    when(messageSearch.error).thenReturn(null);
  });

  group('RoomListController state', () {
    test('initial values', () {
      final controller = makeController();
      expect(controller.query, '');
      expect(controller.isSearchOpen, false);
      expect(controller.isFabOpen, false);
      expect(controller.messageSearch, messageSearch);
    });

    test('creates default messageSearch controller', () {
      final controller = RoomListController(
        matrixService: matrix,
        selectionService: selection,
        preferencesService: prefs,
        spaceRoomsController: spaceRooms,
      );
      expect(controller.messageSearch, isA<RoomListSearchController>());
      controller.dispose();
    });

    test('setQuery updates query and delegates to messageSearch', () {
      final controller = makeController();
      controller.setQuery('hello', scopeRoomIds: {'!a:example.com'});
      expect(controller.query, 'hello');
      verify(
        messageSearch.onQueryChanged(
          'hello',
          scopeRoomIds: {'!a:example.com'},
        ),
      ).called(1);
    });

    test('clearQuery resets query and clears messageSearch', () {
      final controller = makeController()
        ..setQuery('hello')
        ..clearQuery();
      expect(controller.query, '');
      verify(messageSearch.clear()).called(1);
    });

    test('openSearch/closeSearch toggle state', () {
      final controller = makeController();
      controller.openSearch();
      expect(controller.isSearchOpen, true);
      controller.closeSearch();
      expect(controller.isSearchOpen, false);
      expect(controller.query, '');
    });

    test('toggleSearch switches state', () {
      final controller = makeController();
      controller.toggleSearch();
      expect(controller.isSearchOpen, true);
      controller.toggleSearch();
      expect(controller.isSearchOpen, false);
    });

    test('openFab/closeFab toggle state', () {
      final controller = makeController();
      controller.openFab();
      expect(controller.isFabOpen, true);
      controller.closeFab();
      expect(controller.isFabOpen, false);
    });

    test('toggleFab switches state', () {
      final controller = makeController();
      controller.toggleFab();
      expect(controller.isFabOpen, true);
      controller.toggleFab();
      expect(controller.isFabOpen, false);
    });

    test('toggleFab opens FAB from closed', () {
      final controller = makeController();
      expect(controller.isFabOpen, false);
      controller.toggleFab();
      expect(controller.isFabOpen, true);
    });
  });

  group('RoomListController items', () {
    test('items are empty by default', () {
      final controller = makeController();
      expect(controller.items, isEmpty);
    });

    test('items include invited rooms', () {
      final room = MockRoom();
      when(room.id).thenReturn('!invite:example.com');
      when(room.membership).thenReturn(Membership.invite);
      when(room.isSpace).thenReturn(false);
      when(selection.invitedRooms).thenReturn([room]);
      when(selection.summaryFor(room)).thenReturn(summary(roomId: room.id));
      final controller = makeController();
      final items = controller.items;
      expect(items.length, 1);
      expect(items.first, isA<InviteItem>());
    });

    test('items include orphan rooms when no space selected', () {
      final room = MockRoom();
      when(room.id).thenReturn('!orphan:example.com');
      when(room.isFavourite).thenReturn(false);
      when(room.isDirectChat).thenReturn(false);
      when(selection.orphanRooms).thenReturn([room]);
      when(selection.summaryFor(room)).thenReturn(summary(roomId: room.id));
      final controller = makeController();
      final items = controller.items;
      expect(items.length, 2);
      expect(items.first, isA<HeaderItem>());
      expect(items.last, isA<RoomItem>());
    });

    test(
      'search query shorter than min length does not append message items',
      () {
        final controller = makeController();
        controller.setQuery('ab');
        expect(controller.items, isEmpty);
      },
    );

    test('search query appends message search items', () {
      final controller = makeController();
      when(messageSearch.isLoading).thenReturn(true);
      when(messageSearch.totalCount).thenReturn(5);
      controller.setQuery('hello world');
      final items = controller.items;
      expect(items.length, 1);
      expect(items.first, isA<MessageSearchHeaderItem>());
    });

    test('message results and load-more item are appended', () {
      final controller = makeController();
      when(messageSearch.query).thenReturn('hello world');
      when(messageSearch.results).thenReturn([
        MessageSearchResult(
          roomId: '!r:example.com',
          roomName: 'Room',
          senderName: 'Alice',
          senderId: '@alice:example.com',
          body: 'hello world',
          eventId: r'$1',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ]);
      when(messageSearch.nextBatch).thenReturn('next');
      when(messageSearch.isLoading).thenReturn(false);
      controller.setQuery('hello world');
      final items = controller.items;
      expect(items.length, 3);
      expect(items[0], isA<MessageSearchHeaderItem>());
      expect(items[1], isA<MessageSearchResultItem>());
      expect(items[2], isA<LoadMoreMessagesItem>());
    });
  });

  group('RoomListController emptiness', () {
    test('isEmpty true when no rooms and no search results', () {
      final controller = makeController();
      expect(controller.isEmpty, true);
    });

    test('isEmpty false when message search is active', () {
      final controller = makeController();
      when(messageSearch.isLoading).thenReturn(true);
      expect(controller.isEmpty, false);
    });

    test('isEmpty false when rooms exist', () {
      final room = MockRoom();
      when(room.id).thenReturn('!r:example.com');
      when(room.isFavourite).thenReturn(false);
      when(room.isDirectChat).thenReturn(false);
      when(selection.orphanRooms).thenReturn([room]);
      when(selection.summaryFor(room)).thenReturn(summary(roomId: room.id));
      final controller = makeController();
      expect(controller.isEmpty, false);
    });
  });

  group('RoomListController app bar', () {
    test('appBarTitle returns Chats when no space selected', () {
      when(selection.selectedSpaceIds).thenReturn({});
      final controller = makeController();
      expect(controller.appBarTitle(), 'Chats');
    });

    test('appBarTitle returns room displayname for single selection', () {
      const spaceId = '!space:example.com';
      final space = MockRoom();
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(space.getLocalizedDisplayname()).thenReturn('My Space');
      final controller = makeController();
      expect(controller.appBarTitle(), 'My Space');
    });

    test('appBarTitle returns count for multi selection', () {
      when(
        selection.selectedSpaceIds,
      ).thenReturn({'!a:example.com', '!b:example.com'});
      final controller = makeController();
      expect(controller.appBarTitle(), '2 spaces');
    });
  });

  group('RoomListController space empty state', () {
    const spaceId = '!space:example.com';

    test('returns null when no space selected', () {
      when(selection.selectedSpaceIds).thenReturn({});
      final controller = makeController();
      expect(controller.spaceWithNoJoinedRooms(), isNull);
    });

    test('returns null when query is non-empty', () {
      final controller = makeController()..setQuery('hello');
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      expect(controller.spaceWithNoJoinedRooms(), isNull);
    });

    test('returns null when selected id is not a space', () {
      final room = MockRoom();
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(room);
      when(room.isSpace).thenReturn(false);
      final controller = makeController();
      expect(controller.spaceWithNoJoinedRooms(), isNull);
    });

    test('returns null when space has joined rooms', () {
      final space = MockRoom();
      final joined = MockRoom();
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(space.isSpace).thenReturn(true);
      when(selection.roomsForSpace(spaceId)).thenReturn([joined]);
      final controller = makeController();
      expect(controller.spaceWithNoJoinedRooms(), isNull);
    });

    test('returns spaceId when uncached', () {
      final space = MockRoom();
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(space.isSpace).thenReturn(true);
      when(selection.roomsForSpace(spaceId)).thenReturn([]);
      when(spaceRooms.isCached(spaceId)).thenReturn(false);
      final controller = makeController();
      expect(controller.spaceWithNoJoinedRooms(), spaceId);
    });

    test('returns spaceId when cached and loading', () {
      final space = MockRoom();
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(space.isSpace).thenReturn(true);
      when(selection.roomsForSpace(spaceId)).thenReturn([]);
      when(spaceRooms.isCached(spaceId)).thenReturn(true);
      when(
        spaceRooms.getRoomState(spaceId),
      ).thenReturn(const SpaceRoomsState(loading: true));
      final controller = makeController();
      expect(controller.spaceWithNoJoinedRooms(), spaceId);
    });

    test('returns spaceId when cached and has unjoined rooms', () {
      final space = MockRoom();
      const metadata = SpaceRoomMetadata(
        roomId: '!unjoined:example.com',
        name: 'Unjoined',
        memberCount: 1,
        roomType: 'm.room',
      );
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(space.isSpace).thenReturn(true);
      when(selection.roomsForSpace(spaceId)).thenReturn([]);
      when(spaceRooms.isCached(spaceId)).thenReturn(true);
      when(spaceRooms.getRoomState(spaceId)).thenReturn(
        const SpaceRoomsState(
          unjoinedRooms: [metadata],
          subspaces: [],
        ),
      );
      final controller = makeController();
      expect(controller.spaceWithNoJoinedRooms(), spaceId);
    });
  });

  group('RoomListController context menu eligibility', () {
    test(
      'selectedSpaceCanManage true when any selected space is manageable',
      () {
        const spaceId = '!space:example.com';
        final space = MockRoom();
        when(selection.selectedSpaceIds).thenReturn({spaceId});
        when(client.getRoomById(spaceId)).thenReturn(space);
        when(space.canChangeStateEvent('m.space.child')).thenReturn(true);
        final controller = makeController();
        expect(controller.selectedSpaceCanManage, true);
      },
    );

    test('manageableSpaceIds includes manageable spaces', () {
      final space = MockRoom();
      when(space.id).thenReturn('!space:example.com');
      when(space.canChangeStateEvent('m.space.child')).thenReturn(true);
      when(selection.spaces).thenReturn([space]);
      final controller = makeController();
      expect(controller.manageableSpaceIds, {'!space:example.com'});
    });
  });

  group('RoomListController hierarchy fetch', () {
    test('maybeFetchSpaceHierarchy fetches uncached selected spaces', () {
      when(
        selection.selectedSpaceIds,
      ).thenReturn({'!a:example.com', '!b:example.com'});
      when(spaceRooms.isCached('!a:example.com')).thenReturn(false);
      when(spaceRooms.isCached('!b:example.com')).thenReturn(true);
      final controller = makeController();
      controller.maybeFetchSpaceHierarchy();
      verify(spaceRooms.fetchSpaceRooms('!a:example.com')).called(1);
      verifyNever(spaceRooms.fetchSpaceRooms('!b:example.com'));
    });
  });

  group('RoomListController lifecycle', () {
    test('dispose removes listener and disposes messageSearch', () {
      final controller = makeController();
      controller.dispose();
      verify(messageSearch.removeListener(any)).called(1);
      verify(messageSearch.dispose()).called(1);
    });

    test('registers notifyListeners with messageSearch', () {
      makeController();
      verify(messageSearch.addListener(any)).called(1);
    });
  });
}

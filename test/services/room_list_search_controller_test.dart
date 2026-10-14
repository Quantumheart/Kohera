import 'package:fake_async/fake_async.dart';

// Tests pass redundant args to mockito stubs for explicitness.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<SearchIndex>(),
])
import 'room_list_search_controller_test.mocks.dart';

SearchResults _buildSearchResults({
  List<MatrixEvent> events = const [],
  String? nextBatch,
  int? count,
}) {
  return SearchResults(
    searchCategories: ResultCategories(
      roomEvents: ResultRoomEvents(
        results: events
            .map((e) => Result(result: e))
            .toList(),
        nextBatch: nextBatch,
        count: count,
      ),
    ),
  );
}

MatrixEvent _makeMatrixEvent({
  required String eventId,
  required String roomId,
  required String senderId,
  required String body,
  required DateTime originServerTs,
}) {
  return MatrixEvent(
    type: EventTypes.Message,
    content: {'body': body, 'msgtype': 'm.text'},
    senderId: senderId,
    eventId: eventId,
    roomId: roomId,
    originServerTs: originServerTs,
  );
}

void main() {
  late MockClient mockClient;
  late MockSearchIndex mockSearchIndex;
  late RoomListSearchController controller;

  setUp(() {
    mockClient = MockClient();
    mockSearchIndex = MockSearchIndex();
    when(mockClient.rooms).thenReturn([]);
    when(mockSearchIndex.isAvailable).thenReturn(true);
    when(mockSearchIndex.search(
      query: anyNamed('query'),
      roomId: anyNamed('roomId'),
      senderId: anyNamed('senderId'),
      startTs: anyNamed('startTs'),
      endTs: anyNamed('endTs'),
      limit: anyNamed('limit'),
      offset: anyNamed('offset'),
    )).thenAnswer((_) async => const <IndexedMessage>[]);
    when(mockSearchIndex.count(
      roomId: anyNamed('roomId'),
      query: anyNamed('query'),
      senderId: anyNamed('senderId'),
      startTs: anyNamed('startTs'),
      endTs: anyNamed('endTs'),
    )).thenAnswer((_) async => 0);
    when(mockSearchIndex.indexedRoomIds()).thenAnswer((_) async => <String>{});
    controller = RoomListSearchController(
      getClient: () => mockClient,
      searchIndex: mockSearchIndex,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('onQueryChanged', () {
    test('short query clears results and stops loading', () {
      controller.onQueryChanged('ab');

      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.nextBatch, isNull);
    });

    test('valid query sets loading and debounces', () {
      fakeAsync((async) {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.onQueryChanged('hello world');

        expect(controller.isLoading, isTrue);

        when(mockClient.search(
          any,
          nextBatch: anyNamed('nextBatch'),
        ),).thenAnswer((_) async => _buildSearchResults());

        async.elapse(const Duration(milliseconds: 500));

        expect(notifyCount, greaterThan(0));
      });
    });

    test('new query cancels previous debounce', () {
      fakeAsync((async) {
        when(mockClient.search(
          any,
          nextBatch: anyNamed('nextBatch'),
        ),).thenAnswer((_) async => _buildSearchResults());

        controller.onQueryChanged('first query');
        async.elapse(const Duration(milliseconds: 300));

        controller.onQueryChanged('second query');
        async.elapse(const Duration(milliseconds: 500));

        async.flushMicrotasks();
      });
    });
  });

  group('performSearch', () {
    test('parses server results into MessageSearchResult list', () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('General');
      when(mockUser.displayName).thenReturn('Alice');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e1',
                roomId: '!room:example.com',
                senderId: '@alice:example.com',
                body: 'hello world',
                originServerTs: DateTime(2026),
              ),
            ],
            count: 1,
          ),);

      controller.onQueryChanged('hello world');
      await controller.performSearch();

      expect(controller.results, hasLength(1));
      expect(controller.results.first.body, 'hello world');
      expect(controller.results.first.roomName, 'General');
      expect(controller.results.first.senderName, 'Alice');
      expect(controller.isLoading, isFalse);
      expect(controller.totalCount, 1);
    });

    test('skips events with null/empty body', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e1',
                roomId: '!room:example.com',
                senderId: '@a:x.com',
                body: '',
                originServerTs: DateTime(2026),
              ),
            ],
          ),);

      controller.onQueryChanged('hello world');
      await controller.performSearch();

      expect(controller.results, isEmpty);
    });

    test('deduplicates by eventId and sorts by timestamp descending',
        () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$older',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'older',
                originServerTs: DateTime(2026),
              ),
              _makeMatrixEvent(
                eventId: r'$newer',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'newer',
                originServerTs: DateTime(2026, 6),
              ),
            ],
          ),);

      controller.onQueryChanged('test query');
      await controller.performSearch();

      expect(controller.results, hasLength(2));
      expect(controller.results.first.eventId, r'$newer');
      expect(controller.results.last.eventId, r'$older');
    });

    test('sets error on search failure', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenThrow(Exception('server error'));

      controller.onQueryChanged('error query');
      await controller.performSearch();

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);
    });

    test('discards stale results from previous generation', () async {
      var callCount = 0;
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _buildSearchResults(
          events: [
            _makeMatrixEvent(
              eventId: '\$e$callCount',
              roomId: '!r:x',
              senderId: '@a:x',
              body: 'result $callCount',
              originServerTs: DateTime(2026, 1, callCount),
            ),
          ],
        );
      });

      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      final firstSearch = controller.performSearch();
      controller.onQueryChanged('new query');
      await firstSearch;

      expect(controller.results, isEmpty);
    });

    test('loadMore appends to existing results', () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e1',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'first',
                originServerTs: DateTime(2026, 6),
              ),
            ],
            nextBatch: 'batch2',
            count: 2,
          ),);

      controller.onQueryChanged('test query');
      await controller.performSearch();
      expect(controller.results, hasLength(1));

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e2',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'second',
                originServerTs: DateTime(2026),
              ),
            ],
          ),);

      await controller.performSearch(loadMore: true);
      expect(controller.results, hasLength(2));
    });
  });

  group('clear', () {
    test('resets all state', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults());

      controller.onQueryChanged('test query');
      await controller.performSearch();

      controller.clear();

      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.nextBatch, isNull);
      expect(controller.totalCount, isNull);
      expect(controller.query, isEmpty);
    });
  });

  group('FTS5 index search', () {
    test('queries the index with roomId null for global search', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults());
      when(mockSearchIndex.search(
        query: anyNamed('query'),
        roomId: anyNamed('roomId'),
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
        limit: anyNamed('limit'),
        offset: anyNamed('offset'),
      ),).thenAnswer((_) async => const <IndexedMessage>[]);
      when(mockSearchIndex.count(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
      ),).thenAnswer((_) async => 5);

      controller.onQueryChanged('encrypted query');
      await controller.performSearch();

      verify(mockSearchIndex.search(
        query: 'encrypted query',
        roomId: null,
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
        limit: 20,
        offset: anyNamed('offset'),
      ),).called(1);
      verify(mockSearchIndex.count(query: 'encrypted query')).called(1);
    });

    test('totalCount includes server count plus index count', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(count: 3));
      when(mockSearchIndex.count(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
      ),).thenAnswer((_) async => 7);

      controller.onQueryChanged('combined query');
      await controller.performSearch();

      expect(controller.totalCount, 10);
    });

    test('paginates the index via offset on loadMore', () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            nextBatch: 'server-batch2',
            count: 1,
          ),);

      final indexedMessages = List.generate(
        20,
        (i) => IndexedMessage(
          eventId: r'$idx$i',
          roomId: '!room:example.com',
          senderId: '@alice:example.com',
          body: 'encrypted match $i',
          msgtype: 'm.text',
          originServerTs: DateTime(2026, 1, 1, 0, i),
        ),
      );
      when(mockSearchIndex.search(
        query: anyNamed('query'),
        roomId: anyNamed('roomId'),
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
        limit: anyNamed('limit'),
        offset: anyNamed('offset'),
      ),).thenAnswer((invocation) async {
        final offset = invocation.namedArguments[#offset] as int? ?? 0;
        return indexedMessages.skip(offset).take(20).toList();
      });
      when(mockSearchIndex.count(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
      ),).thenAnswer((_) async => 40);

      controller.onQueryChanged('paginated query');
      await controller.performSearch();
      expect(controller.results.length, greaterThan(0));
      expect(controller.nextBatch, isNotNull);

      await controller.performSearch(loadMore: true);

      verify(mockSearchIndex.search(
        query: 'paginated query',
        roomId: null,
        senderId: anyNamed('senderId'),
        startTs: anyNamed('startTs'),
        endTs: anyNamed('endTs'),
        limit: 20,
        offset: 20,
      ),).called(1);
    });

    test('falls back to timeline scan for unindexed encrypted rooms', () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockRoom.id).thenReturn('!encrypted:example.com');
      when(mockRoom.encrypted).thenReturn(true);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Encrypted Room');
      when(mockUser.displayName).thenReturn('Alice');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockClient.getRoomById('!encrypted:example.com'))
          .thenReturn(mockRoom);
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults());
      when(mockSearchIndex.indexedRoomIds())
          .thenAnswer((_) async => <String>{});

      final searchEvent = Event(
        type: EventTypes.Message,
        content: {'body': 'found it', 'msgtype': 'm.text'},
        senderId: '@alice:example.com',
        eventId: r'$fallback1',
        originServerTs: DateTime(2026),
        room: mockRoom,
      );
      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
      ),).thenAnswer((_) async => (
        events: [searchEvent],
        nextBatch: null,
        searchedUntil: null,
      ));

      controller.onQueryChanged('fallback query');
      await controller.performSearch();

      expect(
        controller.results.any((r) => r.eventId == r'$fallback1'),
        isTrue,
      );
      expect(controller.indexingRoomIds, contains('!encrypted:example.com'));
    });
  });
}

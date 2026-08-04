
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/services/room_search_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<RoomSearchService>(),
])
import 'chat_search_controller_test.mocks.dart';

void main() {
  late MockRoomSearchService mockService;
  late ChatSearchController controller;

  RoomSearchResult stubbedResult(String id) {
    return RoomSearchResult(
      message: KoheraMessageDisplay(
        eventId: id,
        senderId: '@alice:example.com',
        senderName: 'Alice',
        body: 'hello',
        messageType: 'm.text',
        eventType: 'm.room.message',
        timestamp: DateTime(2026, 1, 15, 10),
        status: KoheraMessageStatus.sent,
        content: const {},
      ),
      contextBefore: const [],
      contextAfter: const [],
      isEncryptedRoom: false,
    );
  }

  setUp(() {
    mockService = MockRoomSearchService();
    controller = ChatSearchController(
      roomId: '!room:example.com',
      searchService: mockService,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('open / close', () {
    test('open sets isSearching to true', () {
      controller.open();
      expect(controller.isSearching, isTrue);
    });

    test('close resets all state', () {
      controller.open();
      controller.close();
      expect(controller.isSearching, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.nextBatch, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.query, isEmpty);
    });

    test('close resets highlighted event id', () {
      controller.setHighlight('evt1');
      controller.close();
      expect(controller.highlightedEventId, isNull);
    });
  });

  group('onQueryChanged', () {
    test('short query clears results without searching', () {
      controller.open();
      controller.onQueryChanged('a');
      expect(controller.query, 'a');
      expect(controller.results, isEmpty);
      verifyNever(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: anyNamed('nextBatch'),
      ));
    });

    test('trims whitespace from query', () {
      controller.open();
      controller.onQueryChanged('  ab  ');
      expect(controller.query, 'ab');
    });
  });

  group('performSearch', () {
    test('sets results on success', () async {
      controller.open();
      controller.onQueryChanged('hello');

      when(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: anyNamed('nextBatch'),
        senderFilter: anyNamed('senderFilter'),
      )).thenAnswer((_) async => RoomSearchResponse(
            results: [stubbedResult(r'$evt1')],
            isEncryptedRoom: false,
            nextBatch: 'batch2',
            count: 1,
          ));

      await controller.performSearch();

      expect(controller.results, hasLength(1));
      expect(controller.nextBatch, 'batch2');
      expect(controller.count, 1);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
    });

    test('sets error on failure', () async {
      controller.open();
      controller.onQueryChanged('hello');

      when(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: anyNamed('nextBatch'),
        senderFilter: anyNamed('senderFilter'),
      )).thenThrow(Exception('Network error'));

      await controller.performSearch();

      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNotNull);
    });

    test('loadMore appends to existing results', () async {
      controller.open();
      controller.onQueryChanged('hello');

      when(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: argThat(isNull, named: 'nextBatch'),
        senderFilter: anyNamed('senderFilter'),
      )).thenAnswer((_) async => RoomSearchResponse(
            results: [stubbedResult(r'$evt1')],
            isEncryptedRoom: false,
            nextBatch: 'batch2',
            count: 2,
          ));

      await controller.performSearch();
      expect(controller.results, hasLength(1));

      when(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: argThat(equals('batch2'), named: 'nextBatch'),
        senderFilter: anyNamed('senderFilter'),
      )).thenAnswer((_) async => RoomSearchResponse(
            results: [stubbedResult(r'$evt2')],
            isEncryptedRoom: false,
            nextBatch: null,
            count: 2,
          ));

      await controller.performSearch(loadMore: true);
      expect(controller.results, hasLength(2));
      expect(controller.nextBatch, isNull);
    });

    test('skips search when query is too short', () async {
      controller.open();
      controller.onQueryChanged('a');
      await controller.performSearch();
      verifyNever(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: anyNamed('nextBatch'),
      ));
    });
  });

  group('setHighlight', () {
    test('sets highlighted event id', () {
      controller.setHighlight('evt1');
      expect(controller.highlightedEventId, 'evt1');
    });

    test('replaces previous highlight', () {
      controller.setHighlight('evt1');
      controller.setHighlight('evt2');
      expect(controller.highlightedEventId, 'evt2');
    });
  });

  group('notifyListeners', () {
    test('notifies on open', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.open();
      expect(count, greaterThanOrEqualTo(1));
    });

    test('notifies on close', () {
      controller.open();
      var count = 0;
      controller.addListener(() => count++);
      controller.close();
      expect(count, greaterThanOrEqualTo(1));
    });

    test('notifies on setHighlight', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.setHighlight('evt1');
      expect(count, 1);
    });
  });

  group('encrypted room state', () {
    test('tracks isEncryptedRoom from response', () async {
      controller.open();
      controller.onQueryChanged('hello');

      when(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: anyNamed('nextBatch'),
        senderFilter: anyNamed('senderFilter'),
      )).thenAnswer((_) async => const RoomSearchResponse(
            results: [],
            isEncryptedRoom: true,
          ));

      await controller.performSearch();
      expect(controller.isEncryptedRoom, isTrue);
    });
  });

  group('senderFilter', () {
    test('setSenderFilter notifies listeners', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.setSenderFilter('@bob:example.com');
      expect(count, greaterThanOrEqualTo(1));
      expect(controller.senderFilter, '@bob:example.com');
    });

    test('resultSenders extracts unique sender IDs', () async {
      controller.open();
      controller.onQueryChanged('hello');

      when(mockService.search(
        roomId: anyNamed('roomId'),
        query: anyNamed('query'),
        nextBatch: anyNamed('nextBatch'),
        senderFilter: anyNamed('senderFilter'),
      )).thenAnswer((_) async => RoomSearchResponse(
            results: [
              stubbedResult(r'$evt1'),
              stubbedResult(r'$evt2'),
            ],
            isEncryptedRoom: false,
          ));

      await controller.performSearch();
      expect(controller.resultSenders, hasLength(1));
      expect(controller.resultSenders, contains('@alice:example.com'));
    });
  });
}
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/message_search_result.dart';
import 'package:kohera/data/repositories/message_search_repository.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<MessageSearchRepository>()])
import 'room_list_search_controller_test.mocks.dart';

MessageSearchResult _makeResult({
  required String eventId,
  String roomId = '!r:example.com',
  String roomName = 'Room',
  String senderName = 'Alice',
  String senderId = '@alice:example.com',
  String body = 'hello world',
  DateTime? originServerTs,
}) {
  return MessageSearchResult(
    roomId: roomId,
    roomName: roomName,
    senderName: senderName,
    senderId: senderId,
    body: body,
    eventId: eventId,
    originServerTs: originServerTs ?? DateTime(2026),
  );
}

void main() {
  late MockMessageSearchRepository mockRepo;
  late RoomListSearchController controller;

  setUp(() {
    mockRepo = MockMessageSearchRepository();
    controller = RoomListSearchController(searchRepository: mockRepo);
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

        when(mockRepo.searchServer(
          query: anyNamed('query'),
          limit: anyNamed('limit'),
          scopeRoomIds: anyNamed('scopeRoomIds'),
          nextBatch: anyNamed('nextBatch'),
        )).thenAnswer((_) async => const ServerSearchPage());

        async.elapse(const Duration(milliseconds: 500));

        expect(notifyCount, greaterThan(0));
      });
    });

    test('new query cancels previous debounce', () {
      fakeAsync((async) {
        when(mockRepo.searchServer(
          query: anyNamed('query'),
          limit: anyNamed('limit'),
          scopeRoomIds: anyNamed('scopeRoomIds'),
          nextBatch: anyNamed('nextBatch'),
        )).thenAnswer((_) async => const ServerSearchPage());
        when(mockRepo.searchLocal(
          query: anyNamed('query'),
          limit: anyNamed('limit'),
          scopeRoomIds: anyNamed('scopeRoomIds'),
          offset: anyNamed('offset'),
        )).thenAnswer((_) async => const LocalSearchPage());
        when(mockRepo.searchUnindexed(
          query: anyNamed('query'),
          limit: anyNamed('limit'),
          scopeRoomIds: anyNamed('scopeRoomIds'),
        )).thenAnswer((_) async => const UnindexedSearchResult());

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
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$e1')],
            count: 1,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      controller.onQueryChanged('hello world');
      await controller.performSearch();

      expect(controller.results, hasLength(1));
      expect(controller.results.first.body, 'hello world');
      expect(controller.isLoading, isFalse);
      expect(controller.totalCount, 1);
    });

    test('deduplicates by eventId and sorts by timestamp descending',
        () async {
      final older = _makeResult(
        eventId: r'$older',
        body: 'older',
        originServerTs: DateTime(2026),
      );
      final newer = _makeResult(
        eventId: r'$newer',
        body: 'newer',
        originServerTs: DateTime(2026, 6),
      );
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(results: [older, newer]));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      controller.onQueryChanged('test query');
      await controller.performSearch();

      expect(controller.results, hasLength(2));
      expect(controller.results.first.eventId, r'$newer');
      expect(controller.results.last.eventId, r'$older');
    });

    test('sets error on search failure', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenThrow(Exception('server error'));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      controller.onQueryChanged('error query');
      await controller.performSearch();

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);
    });

    test('discards stale results from previous generation', () async {
      var callCount = 0;
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return ServerSearchPage(
          results: [_makeResult(eventId: '\$e$callCount')],
        );
      });
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      final firstSearch = controller.performSearch();
      controller.onQueryChanged('new query');
      await firstSearch;

      expect(controller.results, isEmpty);
    });

    test('loadMore appends to existing results', () async {
      final first = _makeResult(
        eventId: r'$e1',
        body: 'first',
        originServerTs: DateTime(2026, 6),
      );
      final second = _makeResult(
        eventId: r'$e2',
        body: 'second',
        originServerTs: DateTime(2026),
      );
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [first],
            nextBatch: 'batch2',
            count: 2,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      controller.onQueryChanged('test query');
      await controller.performSearch();
      expect(controller.results, hasLength(1));

      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(results: [second]));

      await controller.performSearch(loadMore: true);
      expect(controller.results, hasLength(2));
    });
  });

  group('clear', () {
    test('resets all state', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => const ServerSearchPage());
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

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
    test('totalCount includes server count plus index count', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => const ServerSearchPage(count: 3));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage(count: 7));
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      controller.onQueryChanged('combined query');
      await controller.performSearch();

      expect(controller.totalCount, 10);
    });

    test('paginates the index via offset on loadMore', () async {
      final indexedResults = List.generate(
        20,
        (i) => _makeResult(
          eventId: r'$idx$i',
          body: 'encrypted match $i',
          originServerTs: DateTime(2026, 1, 1, 0, i),
        ),
      );
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => const ServerSearchPage(
            nextBatch: 'server-batch2',
            count: 1,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((invocation) async {
        final offset = invocation.namedArguments[#offset] as int? ?? 0;
        return LocalSearchPage(
          results: indexedResults.skip(offset).take(20).toList(),
          count: 40,
          nextBatch: offset + 20 < 40 ? '${offset + 20}' : null,
        );
      });
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => const UnindexedSearchResult());

      controller.onQueryChanged('paginated query');
      await controller.performSearch();
      expect(controller.results.length, greaterThan(0));
      expect(controller.nextBatch, isNotNull);

      await controller.performSearch(loadMore: true);

      verify(mockRepo.searchLocal(
        query: 'paginated query',
        limit: 20,
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: 20,
      )).called(1);
    });

    test('surfaces indexingRoomIds from fallback', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => const ServerSearchPage());
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => const LocalSearchPage());
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
      )).thenAnswer((_) async => UnindexedSearchResult(
            results: [
              _makeResult(eventId: r'$fallback1', body: 'found it'),
            ],
            indexingRoomIds: {'!encrypted:example.com'},
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

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

void _stubServer(MockMessageSearchRepository mockRepo) {
  when(mockRepo.searchServer(
    query: anyNamed('query'),
    limit: anyNamed('limit'),
    scopeRoomIds: anyNamed('scopeRoomIds'),
    nextBatch: anyNamed('nextBatch'),
  )).thenAnswer((_) async => const ServerSearchPage());
}

void _stubLocal(MockMessageSearchRepository mockRepo) {
  when(mockRepo.searchLocal(
    query: anyNamed('query'),
    limit: anyNamed('limit'),
    scopeRoomIds: anyNamed('scopeRoomIds'),
    offset: anyNamed('offset'),
  )).thenAnswer((_) async => const LocalSearchPage());
}

void _stubUnindexed(MockMessageSearchRepository mockRepo) {
  when(mockRepo.searchUnindexed(
    query: anyNamed('query'),
    limit: anyNamed('limit'),
    scopeRoomIds: anyNamed('scopeRoomIds'),
    shouldAbort: anyNamed('shouldAbort'),
  )).thenAnswer((_) async => const UnindexedSearchResult());
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
        _stubServer(mockRepo);
        _stubLocal(mockRepo);
        _stubUnindexed(mockRepo);

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
      _stubLocal(mockRepo);
      _stubUnindexed(mockRepo);

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
      _stubLocal(mockRepo);
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('test query');
      await controller.performSearch();

      expect(controller.results, hasLength(2));
      expect(controller.results.first.eventId, r'$newer');
      expect(controller.results.last.eventId, r'$older');
    });

    test('sets error when all sources fail and no results', () async {
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
      )).thenThrow(Exception('index error'));
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        shouldAbort: anyNamed('shouldAbort'),
      )).thenThrow(Exception('fallback error'));

      controller.onQueryChanged('error query');
      await controller.performSearch();

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);
      expect(controller.results, isEmpty);
    });

    test('shows partial results when server fails but index succeeds',
        () async {
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
      )).thenAnswer((_) async => LocalSearchPage(
            results: [_makeResult(eventId: r'$idx1', body: 'encrypted')],
            count: 1,
          ));
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('partial query');
      await controller.performSearch();

      expect(controller.error, isNull);
      expect(controller.results, hasLength(1));
      expect(controller.results.first.eventId, r'$idx1');
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
      _stubLocal(mockRepo);
      _stubUnindexed(mockRepo);

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
      _stubLocal(mockRepo);
      _stubUnindexed(mockRepo);

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
      _stubServer(mockRepo);
      _stubLocal(mockRepo);
      _stubUnindexed(mockRepo);

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
      _stubUnindexed(mockRepo);

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
      _stubUnindexed(mockRepo);

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

    test('surfaces fallback results', () async {
      _stubServer(mockRepo);
      _stubLocal(mockRepo);
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        shouldAbort: anyNamed('shouldAbort'),
      )).thenAnswer((_) async => UnindexedSearchResult(
            results: [
              _makeResult(eventId: r'$fallback1', body: 'found it'),
            ],
            count: 1,
          ));

      controller.onQueryChanged('fallback query');
      await controller.performSearch();

      expect(
        controller.results.any((r) => r.eventId == r'$fallback1'),
        isTrue,
      );
    });
  });

  group('source exhaustion', () {
    test('loadMore skips exhausted index source', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s1')],
            nextBatch: 'server-batch2',
            count: 5,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => LocalSearchPage(
            results: [_makeResult(eventId: r'$i1')],
            count: 1,
          ));
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('exhaust test');
      await controller.performSearch();

      await controller.performSearch(loadMore: true);

      verify(mockRepo.searchLocal(
        query: 'exhaust test',
        limit: 20,
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).called(1);
    });

    test('loadMore skips exhausted server source', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s1')],
            count: 1,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => LocalSearchPage(
            results: [_makeResult(eventId: r'$i1')],
            nextBatch: '20',
            count: 40,
          ));
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('server exhaust');
      await controller.performSearch();

      await controller.performSearch(loadMore: true);

      verify(mockRepo.searchServer(
        query: 'server exhaust',
        limit: 20,
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).called(1);
    });

    test('nextBatch becomes null when all sources exhausted', () async {
      _stubServer(mockRepo);
      _stubLocal(mockRepo);
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('all exhausted');
      await controller.performSearch();

      expect(controller.nextBatch, isNull);
    });
  });

  group('count stability', () {
    test('totalCount stays stable on loadMore with fallback matches',
        () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s1')],
            nextBatch: 'batch2',
            count: 2,
          ));
      _stubLocal(mockRepo);
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        shouldAbort: anyNamed('shouldAbort'),
      )).thenAnswer((_) async => UnindexedSearchResult(
            results: [_makeResult(eventId: r'$f1', body: 'fallback')],
            count: 1,
          ));

      controller.onQueryChanged('count test');
      await controller.performSearch();

      final initialCount = controller.totalCount;
      expect(initialCount, 3);

      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s2')],
            count: 2,
          ));

      await controller.performSearch(loadMore: true);

      expect(controller.totalCount, initialCount);
    });
  });

  group('count persistence across loadMore (issue 3)', () {
    test('totalCount keeps index count after index exhausts', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s1', body: 'server')],
            nextBatch: 'server-batch2',
            count: 50,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => LocalSearchPage(
            results: [_makeResult(eventId: r'$i1', body: 'index')],
            count: 5,
          ));
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('persist test');
      await controller.performSearch();
      expect(controller.totalCount, 55);

      await controller.performSearch(loadMore: true);
      expect(controller.totalCount, 55);
    });

    test('totalCount keeps server count after server exhausts', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s1', body: 'server')],
            count: 50,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => LocalSearchPage(
            results: [_makeResult(eventId: r'$i1', body: 'index')],
            nextBatch: '20',
            count: 40,
          ));
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('server persist');
      await controller.performSearch();
      expect(controller.totalCount, 90);

      await controller.performSearch(loadMore: true);
      expect(controller.totalCount, 90);
    });
  });

  group('partial failure on loadMore (issue 4)', () {
    test('server failure keeps pagination and shows partialError', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => ServerSearchPage(
            results: [_makeResult(eventId: r'$s1', body: 'server one')],
            nextBatch: 'server-batch2',
            count: 5,
          ));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenAnswer((_) async => LocalSearchPage(
            results: [_makeResult(eventId: r'$i1', body: 'index one')],
            nextBatch: '20',
            count: 3,
          ));
      _stubUnindexed(mockRepo);

      controller.onQueryChanged('blip query');
      await controller.performSearch();
      expect(controller.error, isNull);
      expect(controller.partialError, isNull);
      expect(controller.totalCount, 8);

      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenThrow(Exception('network blip'));

      await controller.performSearch(loadMore: true);

      expect(controller.error, isNull);
      expect(controller.partialError, isNotNull);
      expect(controller.results, isNotEmpty);
      // Server token preserved so a retry can continue paging.
      expect(controller.nextBatch, isNotNull);
      expect(controller.totalCount, 8);
    });

    test('only-index failure does not blame the server', () async {
      when(mockRepo.searchServer(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        nextBatch: anyNamed('nextBatch'),
      )).thenThrow(Exception('index down'));
      when(mockRepo.searchLocal(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        offset: anyNamed('offset'),
      )).thenThrow(Exception('index isolate crashed'));
      when(mockRepo.searchUnindexed(
        query: anyNamed('query'),
        limit: anyNamed('limit'),
        scopeRoomIds: anyNamed('scopeRoomIds'),
        shouldAbort: anyNamed('shouldAbort'),
      )).thenAnswer((_) async => UnindexedSearchResult(
            results: [_makeResult(eventId: r'$f1', body: 'fallback only')],
            count: 1,
          ));

      controller.onQueryChanged('index only fails');
      await controller.performSearch();

      expect(controller.error, isNull);
      expect(controller.partialError, isNotNull);
      expect(controller.results, hasLength(1));
    });
  });
}

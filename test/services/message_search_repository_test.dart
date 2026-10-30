import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/message_search_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'message_search_repository_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient client;
  late MockRoom room;
  late CachedStreamController<SyncUpdate> syncController;
  late CachedStreamController<String> keyController;
  late _FakeSearchIndex index;
  late MessageIndexerService indexer;
  late MessageSearchRepository repository;

  setUp(() {
    client = MockClient();
    room = MockRoom();
    syncController = CachedStreamController<SyncUpdate>();
    keyController = CachedStreamController<String>();
    index = _FakeSearchIndex();

    when(client.rooms).thenReturn([room]);
    when(client.getRoomById('!r:s')).thenReturn(room);
    when(client.onSync).thenReturn(syncController);
    when(client.database).thenReturn(_FakeDatabaseApi());
    when(client.encryption).thenReturn(null);

    when(room.id).thenReturn('!r:s');
    when(room.membership).thenReturn(Membership.join);
    when(room.encrypted).thenReturn(true);
    when(room.onSessionKeyReceived).thenReturn(keyController);
    when(room.client).thenReturn(client);
    when(room.getLocalizedDisplayname()).thenReturn('Room');
    final user = MockUser();
    when(user.displayName).thenReturn('Alice');
    when(room.unsafeGetUserFromMemoryOrFallback(any)).thenReturn(user);

    indexer = MessageIndexerService(
      matrixClientService: MatrixClientService(client),
      clientName: 'test',
      databaseOverride: index,
    );
    repository = MessageSearchRepository(
      clientService: MatrixClientService(client),
      indexer: indexer,
    );
  });

  tearDown(() async {
    await indexer.waitForIdle();
    indexer.dispose();
  });

  group('searchLocal', () {
    test('computes the count only on the first page (issue 9)', () async {
      await repository.searchLocal(query: 'hello', limit: 20);
      expect(index.searchCalls, 1);
      expect(index.countCalls, 1);

      await repository.searchLocal(query: 'hello', limit: 20, offset: 20);
      expect(index.searchCalls, 2);
      // No second COUNT round-trip for paginated pages.
      expect(index.countCalls, 1);
    });

    test('first page carries the count, later pages omit it (issue 9)',
        () async {
      index.countResult = 42;

      final page1 = await repository.searchLocal(query: 'hello', limit: 20);
      expect(page1.count, 42);

      final page2 =
          await repository.searchLocal(query: 'hello', limit: 20, offset: 20);
      expect(page2.count, isNull);
    });

    test('empty scope returns nothing without touching the index (issue 1)',
        () async {
      final page = await repository.searchLocal(
        query: 'hello',
        limit: 20,
        scopeRoomIds: {},
      );
      expect(page.results, isEmpty);
      expect(page.count, isNull);
      expect(page.nextBatch, isNull);
      expect(index.searchCalls, 0);
      expect(index.countCalls, 0);
    });
  });

  group('searchUnindexed', () {
    test('covers a room whose backfill is in progress (issue 6)', () async {
      final blocker = Completer<void>();
      when(client.database).thenReturn(_BlockingDatabaseApi(blocker));

      final hit = MockEvent();
      when(hit.type).thenReturn(EventTypes.Message);
      when(hit.senderId).thenReturn('@u:s');
      when(hit.eventId).thenReturn(r'$hit');
      when(hit.originServerTs).thenReturn(DateTime(2024));
      when(hit.content).thenReturn({'msgtype': 'm.text', 'body': 'needle'});

      when(room.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
      )).thenAnswer(
        (_) async => (events: [hit], nextBatch: null, searchedUntil: null),
      );

      await indexer.init();
      // Start a backfill that blocks, so '!r:s' is mid-backfill: the old
      // code excluded it from the fallback while the index only held its
      // partial rows, so matches were missed entirely.
      await indexer.ensureRoomIndexed(room);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(indexer.indexingRoomIds, contains('!r:s'));

      final result = await repository.searchUnindexed(
        query: 'needle',
        limit: 20,
      );

      expect(result.results, hasLength(1));
      expect(result.results.first.eventId, r'$hit');
      expect(result.count, 1);

      blocker.complete();
      await indexer.waitForIdle();
    });

    test('skips rooms the user left (issue 2)', () async {
      when(room.membership).thenReturn(Membership.leave);

      final result = await repository.searchUnindexed(
        query: 'needle',
        limit: 20,
      );

      expect(result.results, isEmpty);
      verifyNever(room.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
      ));
    });
  });
}

class _FakeSearchIndex implements SearchIndex {
  int searchCalls = 0;
  int countCalls = 0;
  int countResult = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<List<IndexedMessage>> search({
    required String query,
    String? roomId,
    Set<String>? roomIds,
    String? senderId,
    int? startTs,
    int? endTs,
    int limit = 50,
    int offset = 0,
    bool onlyIndexedRooms = false,
  }) async {
    searchCalls++;
    return const [];
  }

  @override
  Future<int> count({
    String? roomId,
    Set<String>? roomIds,
    String? query,
    String? senderId,
    int? startTs,
    int? endTs,
    bool onlyIndexedRooms = false,
  }) async {
    countCalls++;
    return countResult;
  }

  @override
  Future<void> upsert(IndexedMessage message) async {}

  @override
  Future<void> upsertBatch(List<IndexedMessage> messages) async {}

  @override
  Future<void> remove(String eventId) async {}

  @override
  Future<void> removeRoom(String roomId) async {}

  @override
  Future<int> countAll() async => 0;

  @override
  Future<bool> isRoomIndexed(String roomId) async => false;

  @override
  Future<Set<String>> indexedRoomIds() async => {};

  @override
  Future<void> markRoomIndexed(String roomId, int eventCount) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

class _FakeDatabaseApi extends Fake implements DatabaseApi {
  @override
  Future<Event?> getEventById(String eventId, Room room) async => null;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async =>
      const <Event>[];
}

class _BlockingDatabaseApi extends _FakeDatabaseApi {
  _BlockingDatabaseApi(this.blocker);

  final Completer<void> blocker;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    await blocker.future;
    return const <Event>[];
  }
}

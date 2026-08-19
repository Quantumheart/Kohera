import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late MessageSearchDatabase searchDb;
  late int dbCounter;

  setUp(() async {
    dbCounter = DateTime.now().microsecondsSinceEpoch;
    db = await databaseFactory.openDatabase(':memory:$dbCounter');
    searchDb = MessageSearchDatabase(clientName: 'test', overrideDb: db);
    await searchDb.ensureSchema();
  });

  tearDown(() async {
    await searchDb.close();
    await db.close();
  });

  group('schema', () {
    test('ensureSchema creates the FTS5 virtual table', () async {
      final seed = DateTime.now().microsecondsSinceEpoch;
      final freshDb = await databaseFactory.openDatabase(':memory:$seed');
      final freshSearchDb = MessageSearchDatabase(
        clientName: 'test',
        overrideDb: freshDb,
      );
      await freshSearchDb.ensureSchema();
      final rows = await freshDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='message_search'",
      );
      expect(rows, hasLength(1));
      await freshSearchDb.close();
      await freshDb.close();
    });
  });

  group('upsert', () {
    test('stores and retrieves a message', () async {
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'hello world',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      final results = await searchDb.search(query: 'hello');
      expect(results, hasLength(1));
      expect(results.first.eventId, r'$e1');
    });

    test('upsertBatch stores multiple messages in one transaction', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'alpha',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'beta',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      final results = await searchDb.search(query: 'alpha');
      expect(results, hasLength(1));
      final betaResults = await searchDb.search(query: 'beta');
      expect(betaResults, hasLength(1));
    });

    test('upsert replaces existing event by event_id', () async {
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'old',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'new',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      final results = await searchDb.search(query: 'new');
      expect(results, hasLength(1));
      expect(results.first.body, 'new');
      final oldResults = await searchDb.search(query: 'old');
      expect(oldResults, isEmpty);
    });
  });

  group('remove', () {
    test('remove deletes by event_id', () async {
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'hello',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      await searchDb.remove(r'$e1');
      final results = await searchDb.search(query: 'hello');
      expect(results, isEmpty);
    });

    test('removeRoom deletes all messages in a room', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'hello',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!other:s',
          senderId: '@u:s',
          body: 'hello',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      await searchDb.removeRoom('!r:s');
      final inRoom = await searchDb.search(query: 'hello', roomId: '!r:s');
      expect(inRoom, isEmpty);
      final otherRoom = await searchDb.search(
        query: 'hello',
        roomId: '!other:s',
      );
      expect(otherRoom, hasLength(1));
    });
  });

  group('search', () {
    test('filters by roomId', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'hello',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!other:s',
          senderId: '@u:s',
          body: 'hello',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      final results = await searchDb.search(query: 'hello', roomId: '!r:s');
      expect(results, hasLength(1));
      expect(results.first.eventId, r'$e1');
    });

    test('supports limit and offset', () async {
      await searchDb.upsertBatch([
        for (var i = 0; i < 5; i++)
          IndexedMessage(
            eventId: '\$e$i',
            roomId: '!r:s',
            senderId: '@u:s',
            body: 'common word',
            msgtype: 'm.text',
            originServerTs: DateTime(2024, 1, i + 1),
          ),
      ]);
      final page1 = await searchDb.search(
        query: 'common',
        roomId: '!r:s',
        limit: 2,
      );
      expect(page1, hasLength(2));
      final page2 = await searchDb.search(
        query: 'common',
        roomId: '!r:s',
        limit: 2,
        offset: 2,
      );
      expect(page2, hasLength(2));
      final page3 = await searchDb.search(
        query: 'common',
        roomId: '!r:s',
        limit: 2,
        offset: 4,
      );
      expect(page3, hasLength(1));
    });

    test('empty query returns no results', () async {
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'hello',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      final results = await searchDb.search(query: '');
      expect(results, isEmpty);
    });

    test('sanitizes FTS5 special characters without crashing', () async {
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'say "hello" (world) *star*',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      final results = await searchDb.search(query: '"hello" (world) *star*');
      expect(results, hasLength(1));
    });
  });

  group('count', () {
    test('countAll returns total rows', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'alpha',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!other:s',
          senderId: '@u:s',
          body: 'beta',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      expect(await searchDb.countAll(), 2);
    });

    test('count with query filters by match', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'alpha beta',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'beta gamma',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      expect(await searchDb.count(query: 'alpha'), 1);
      expect(await searchDb.count(query: 'beta'), 2);
    });

    test('count with roomId and query', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'alpha',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!other:s',
          senderId: '@u:s',
          body: 'alpha',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      expect(await searchDb.count(roomId: '!r:s', query: 'alpha'), 1);
    });
  });

  group('clear', () {
    test('removes all rows', () async {
      await searchDb.upsertBatch([
        IndexedMessage(
          eventId: r'$e1',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'alpha',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
        IndexedMessage(
          eventId: r'$e2',
          roomId: '!other:s',
          senderId: '@u:s',
          body: 'beta',
          msgtype: 'm.text',
          originServerTs: DateTime(2024, 1, 2),
        ),
      ]);
      await searchDb.clear();
      expect(await searchDb.countAll(), 0);
    });
  });

  group('availability', () {
    test('isAvailable true when overrideDb is provided', () {
      expect(searchDb.isAvailable, isTrue);
    });
  });
}

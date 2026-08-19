import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'message_indexer_service_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Encryption>(),
  MockSpec<Event>(),
  MockSpec<DatabaseApi>(),
])
class _FakeDatabaseApi extends Fake implements DatabaseApi {
  final Map<String, Event> _eventsById = {};

  void storeEvent(Event event) {
    _eventsById[event.eventId] = event;
  }

  @override
  Future<Event?> getEventById(String eventId, Room room) async =>
      _eventsById[eventId];

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async => const <Event>[];
}

Event _messageEvent({
  required String eventId,
  required String roomId,
  required String body,
  String? editTargetId,
  String msgtype = 'm.text',
  DateTime? originServerTs,
}) {
  final ev = MockEvent();
  when(ev.eventId).thenReturn(eventId);
  when(ev.roomId).thenReturn(roomId);
  when(ev.senderId).thenReturn('@u:s');
  when(ev.type).thenReturn('m.room.message');
  when(ev.messageType).thenReturn(msgtype);
  when(ev.body).thenReturn(body);
  when(ev.redacted).thenReturn(false);
  when(ev.originServerTs).thenReturn(originServerTs ?? DateTime(2024));
  when(
    ev.relationshipType,
  ).thenReturn(editTargetId != null ? 'm.replace' : null);
  when(ev.relationshipEventId).thenReturn(editTargetId);
  when(ev.content).thenReturn(
    editTargetId != null
        ? {
            'msgtype': msgtype,
            'body': '* $body',
            'm.new_content': {'msgtype': msgtype, 'body': body},
            'm.relates_to': {'rel_type': 'm.replace', 'event_id': editTargetId},
          }
        : {'msgtype': msgtype, 'body': body},
  );
  return ev;
}

Event _encryptedEvent({
  required String eventId,
  required String roomId,
  bool decryptable = false,
}) {
  final ev = MockEvent();
  when(ev.eventId).thenReturn(eventId);
  when(ev.roomId).thenReturn(roomId);
  when(ev.senderId).thenReturn('@u:s');
  when(ev.type).thenReturn('m.room.encrypted');
  when(
    ev.messageType,
  ).thenReturn(decryptable ? 'm.text' : MessageTypes.BadEncrypted);
  when(ev.body).thenReturn('Unable to decrypt');
  when(ev.redacted).thenReturn(false);
  when(ev.originServerTs).thenReturn(DateTime(2024));
  when(ev.relationshipType).thenReturn(null);
  when(ev.relationshipEventId).thenReturn(null);
  when(ev.content).thenReturn({});
  return ev;
}

MatrixEvent _matrixEventFromEvent(Event event) => MatrixEvent(
  type: event.type,
  content: Map<String, Object?>.from(event.content),
  senderId: event.senderId,
  eventId: event.eventId,
  originServerTs: event.originServerTs,
  roomId: event.roomId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockClient client;
  late MockRoom room;
  late CachedStreamController<SyncUpdate> syncController;
  late CachedStreamController<String> keyController;
  late Database db;
  late MessageSearchDatabase searchDb;
  late MessageIndexerService indexer;

  setUp(() async {
    client = MockClient();
    room = MockRoom();
    syncController = CachedStreamController<SyncUpdate>();
    keyController = CachedStreamController<String>();

    when(client.rooms).thenReturn([room]);
    when(client.getRoomById('!r:s')).thenReturn(room);
    when(client.onSync).thenReturn(syncController);
    when(client.database).thenReturn(_FakeDatabaseApi());
    when(client.encryption).thenReturn(null);

    when(room.id).thenReturn('!r:s');
    when(room.onSessionKeyReceived).thenReturn(keyController);
    when(room.client).thenReturn(client);

    final seed = DateTime.now().microsecondsSinceEpoch;
    db = await databaseFactory.openDatabase(':memory:$seed');
    searchDb = MessageSearchDatabase(clientName: 'test', overrideDb: db);
    await searchDb.ensureSchema();
    indexer = MessageIndexerService(
      client: client,
      clientName: 'test',
      databaseOverride: searchDb,
    );
  });

  tearDown(() async {
    await indexer.waitForIdle();
    indexer.dispose();
    await searchDb.close();
    await db.close();
  });

  /// Marks the room as indexed so sync events are processed by the indexer.
  /// In the new lazy architecture, sync events are only processed for rooms
  /// that have been explicitly indexed via [MessageIndexerService.ensureRoomIndexed].
  Future<void> markRoomIndexed() async {
    await indexer.ensureRoomIndexed(room);
    await indexer.waitForIdle();
  }

  group('init', () {
    test('subscribes to client.onSync', () async {
      var synced = false;
      syncController.stream.listen((_) => synced = true);
      await indexer.init();
      syncController.add(SyncUpdate(nextBatch: 'b1'));
      await pumpEventQueue();
      expect(synced, isTrue);
    });

    test('does not open the database on init', () async {
      // init() should be near-zero cost — no DB open, no backfill.
      await indexer.init();
      expect(indexer.isIndexing, isFalse);
      expect(indexer.indexedCount, 0);
    });
  });

  group('ensureRoomIndexed', () {
    test('backfills room events on first call', () async {
      final stored = [
        _messageEvent(eventId: r'$b1', roomId: '!r:s', body: 'backfill one'),
        _messageEvent(eventId: r'$b2', roomId: '!r:s', body: 'backfill two'),
      ];
      final fakeDb = _FakeBackfillDatabase(stored);
      when(client.database).thenReturn(fakeDb);
      when(client.encryption).thenReturn(null);

      await indexer.init();
      await indexer.ensureRoomIndexed(room);
      await indexer.waitForIdle();

      final results = await searchDb.search(query: 'backfill', roomId: '!r:s');
      expect(results, hasLength(2));
    });

    test('is a no-op when room already indexed', () async {
      // Seed the index.
      await searchDb.upsert(
        IndexedMessage(
          eventId: r'$seed',
          roomId: '!r:s',
          senderId: '@u:s',
          body: 'seed',
          msgtype: 'm.text',
          originServerTs: DateTime(2024),
        ),
      );
      await searchDb.markRoomIndexed('!r:s', 1);

      final stored = [
        _messageEvent(eventId: r'$b1', roomId: '!r:s', body: 'backfill one'),
      ];
      final fakeDb = _FakeBackfillDatabase(stored);
      when(client.database).thenReturn(fakeDb);

      await indexer.init();
      await indexer.ensureRoomIndexed(room);
      await indexer.waitForIdle();

      // The existing seed is still there, but backfill one was NOT indexed
      // (room was already marked as indexed).
      final results = await searchDb.search(query: 'backfill', roomId: '!r:s');
      expect(results, isEmpty);
      final seedResults = await searchDb.search(query: 'seed', roomId: '!r:s');
      expect(seedResults, hasLength(1));
    });

    test('subscribes to room key stream for late decryption', () async {
      when(client.encryption).thenReturn(null);
      await indexer.init();
      await indexer.ensureRoomIndexed(room);
      await indexer.waitForIdle();

      var keyReceived = false;
      keyController.stream.listen((_) => keyReceived = true);
      keyController.add('session-id');
      await pumpEventQueue();
      expect(keyReceived, isTrue);
    });
  });

  group('sync indexing (gated by indexed rooms)', () {
    test('indexes a decrypted message event for an indexed room', () async {
      final ev = _messageEvent(
        eventId: r'$e1',
        roomId: '!r:s',
        body: 'hello world',
      );
      when(client.encryption).thenReturn(null);
      await indexer.init();
      await markRoomIndexed();

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(events: [_matrixEventFromEvent(ev)]),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      final results = await searchDb.search(query: 'hello', roomId: '!r:s');
      expect(results, hasLength(1));
      expect(results.first.body, 'hello world');
    });

    test('skips sync events for non-indexed rooms', () async {
      final ev = _messageEvent(
        eventId: r'$skip1',
        roomId: '!r:s',
        body: 'should not be indexed',
      );
      when(client.encryption).thenReturn(null);
      await indexer.init();
      // Do NOT call markRoomIndexed — room is not indexed.

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(events: [_matrixEventFromEvent(ev)]),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      final results = await searchDb.search(query: 'should', roomId: '!r:s');
      expect(results, isEmpty);
    });

    test('skips undecryptable encrypted events', () async {
      final ev = _encryptedEvent(eventId: r'$enc1', roomId: '!r:s');
      final encryption = MockEncryption();
      when(encryption.decryptRoomEvent(any)).thenAnswer((_) async => ev);
      when(client.encryption).thenReturn(encryption);
      await indexer.init();
      await markRoomIndexed();

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(events: [_matrixEventFromEvent(ev)]),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      final results = await searchDb.search(
        query: 'Unable to decrypt',
        roomId: '!r:s',
      );
      expect(results, isEmpty);
    });

    test('decrypts and indexes encrypted events when possible', () async {
      final decrypted = _messageEvent(
        eventId: r'$dec1',
        roomId: '!r:s',
        body: 'secret text',
      );
      final encrypted = _encryptedEvent(
        eventId: r'$dec1',
        roomId: '!r:s',
        decryptable: true,
      );
      final encryption = MockEncryption();
      when(encryption.decryptRoomEvent(any)).thenAnswer((_) async => decrypted);
      when(client.encryption).thenReturn(encryption);
      await indexer.init();
      await markRoomIndexed();

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [_matrixEventFromEvent(encrypted)],
                ),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      final results = await searchDb.search(query: 'secret', roomId: '!r:s');
      expect(results, hasLength(1));
      expect(results.first.body, 'secret text');
    });

    test('indexes edit under original event_id', () async {
      final original = _messageEvent(
        eventId: r'$orig',
        roomId: '!r:s',
        body: 'old body',
      );
      final edit = _messageEvent(
        eventId: r'$edit',
        roomId: '!r:s',
        body: 'new body',
        editTargetId: r'$orig',
      );
      when(client.encryption).thenReturn(null);
      await indexer.init();
      await markRoomIndexed();

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    _matrixEventFromEvent(original),
                    _matrixEventFromEvent(edit),
                  ],
                ),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      final newResults = await searchDb.search(query: 'new', roomId: '!r:s');
      expect(newResults, hasLength(1));
      expect(newResults.first.eventId, r'$orig');
      expect(newResults.first.body, 'new body');

      final oldResults = await searchDb.search(query: 'old', roomId: '!r:s');
      expect(oldResults, isEmpty);
    });

    test('removes redacted event from index', () async {
      final message = _messageEvent(
        eventId: r'$red1',
        roomId: '!r:s',
        body: 'delete me',
      );
      final redaction = MatrixEvent(
        type: 'm.room.redaction',
        content: {},
        senderId: '@u:s',
        eventId: r'$redact',
        originServerTs: DateTime(2024, 1, 2),
        redacts: r'$red1',
        roomId: '!r:s',
      );
      when(client.encryption).thenReturn(null);
      await indexer.init();
      await markRoomIndexed();

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    _matrixEventFromEvent(message),
                    redaction,
                  ],
                ),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      final results = await searchDb.search(query: 'delete', roomId: '!r:s');
      expect(results, isEmpty);
    });
  });

  group('late key arrival', () {
    test('re-indexes pending event when key arrives', () async {
      final decrypted = _messageEvent(
        eventId: r'$late1',
        roomId: '!r:s',
        body: 'now decryptable',
      );
      final encrypted = _encryptedEvent(
        eventId: r'$late1',
        roomId: '!r:s',
        decryptable: true,
      );
      final encryption = MockEncryption();
      when(encryption.decryptRoomEvent(any)).thenAnswer((_) async => encrypted);
      when(client.encryption).thenReturn(encryption);
      await indexer.init();
      await markRoomIndexed();

      syncController.add(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              '!r:s': JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [_matrixEventFromEvent(encrypted)],
                ),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
      await indexer.waitForIdle();

      // Event is pending (undecryptable).
      when(encryption.decryptRoomEvent(any)).thenAnswer((_) async => decrypted);
      final fakeDb = client.database as _FakeDatabaseApi;
      fakeDb.storeEvent(encrypted);

      keyController.add('session-id');
      await pumpEventQueue();
      await indexer.waitForIdle();

      final results = await searchDb.search(
        query: 'decryptable',
        roomId: '!r:s',
      );
      expect(results, hasLength(1));
      expect(results.first.body, 'now decryptable');
    });
  });
}

class _FakeBackfillDatabase extends _FakeDatabaseApi {
  _FakeBackfillDatabase(this.events);

  final List<Event> events;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    if (start >= events.length) return const [];
    final end = (limit == null)
        ? events.length
        : (start + limit).clamp(0, events.length);
    return events.sublist(start, end);
  }
}

Future<void> pumpEventQueue() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

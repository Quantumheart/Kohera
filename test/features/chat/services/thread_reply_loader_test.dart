import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/services/thread_reply_loader.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<MatrixService>(),
])
import 'thread_reply_loader_test.mocks.dart';

MatrixEvent _msgEvent(String id, {int ts = 0}) {
  return MatrixEvent(
    type: 'm.room.message',
    content: {'body': 'reply $id', 'msgtype': 'm.text'},
    senderId: '@alice:example.com',
    eventId: id,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    roomId: '!room:example.com',
  );
}

void main() {
  late MockMatrixService mockMatrix;
  late MockClient mockClient;
  late MockRoom mockRoom;

  const roomId = '!room:example.com';
  const rootId = '\$root:example.com';

  setUp(() {
    mockMatrix = MockMatrixService();
    mockClient = MockClient();
    mockRoom = MockRoom();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.getRoomById(roomId)).thenReturn(mockRoom);
    when(mockRoom.id).thenReturn(roomId);
    when(mockRoom.client).thenReturn(mockClient);
  });

  group('ThreadReplyLoader.loadRoot', () {
    test('returns true and populates state when root event found', () async {
      final rootEvent = Event.fromMatrixEvent(_msgEvent(rootId, ts: 100), mockRoom);
      when(mockRoom.getEventById(rootId))
          .thenAnswer((_) async => rootEvent);
      when(mockClient.getRelatingEventsWithRelType(
        roomId,
        rootId,
        RelationshipTypes.thread,
        limit: anyNamed('limit'),
        from: argThat(isNull, named: 'from'),
      )).thenAnswer((_) async => GetRelatingEventsWithRelTypeResponse(
        chunk: [_msgEvent('\$r1:example.com', ts: 200)],
        nextBatch: 'batch1',
      ));

      final loader = ThreadReplyLoader();
      final found = await loader.loadRoot(mockMatrix, roomId, rootId);

      expect(found, isTrue);
      expect(loader.rootEvent, isNotNull);
      expect(loader.rootEvent!.eventId, rootId);
      expect(loader.replyIds, ['\$r1:example.com']);
      expect(loader.hasMore, isTrue);
      // seedEvents = root + replies
      expect(loader.seedEvents.length, 2);
      expect(loader.seedEvents.first.eventId, rootId);
      loader.dispose();
    });

    test('returns false when root event not found', () async {
      when(mockRoom.getEventById(rootId))
          .thenAnswer((_) async => null);
      when(mockClient.getRelatingEventsWithRelType(
        roomId,
        rootId,
        RelationshipTypes.thread,
        limit: anyNamed('limit'),
        from: argThat(isNull, named: 'from'),
      )).thenAnswer((_) async => GetRelatingEventsWithRelTypeResponse(
        chunk: [],
        nextBatch: null,
      ));

      final loader = ThreadReplyLoader();
      final found = await loader.loadRoot(mockMatrix, roomId, rootId);

      expect(found, isFalse);
      expect(loader.rootEvent, isNull);
      expect(loader.replyIds, isEmpty);
      expect(loader.hasMore, isFalse);
      // seedEvents with no root = just replies (empty)
      expect(loader.seedEvents, isEmpty);
      loader.dispose();
    });

    test('returns false when room is null', () async {
      when(mockClient.getRoomById(roomId)).thenReturn(null);

      final loader = ThreadReplyLoader();
      final found = await loader.loadRoot(mockMatrix, roomId, rootId);

      expect(found, isFalse);
      loader.dispose();
    });
  });

  group('ThreadReplyLoader.loadMoreReplies', () {
    test('loads next page and deduplicates by eventId', () async {
      // First load root with one reply and a nextBatch.
      final rootEvent = Event.fromMatrixEvent(_msgEvent(rootId, ts: 100), mockRoom);
      when(mockRoom.getEventById(rootId))
          .thenAnswer((_) async => rootEvent);
      when(mockClient.getRelatingEventsWithRelType(
        roomId,
        rootId,
        RelationshipTypes.thread,
        limit: anyNamed('limit'),
        from: argThat(isNull, named: 'from'),
      )).thenAnswer((_) async => GetRelatingEventsWithRelTypeResponse(
        chunk: [_msgEvent('\$r1:example.com', ts: 200)],
        nextBatch: 'batch1',
      ));

      final loader = ThreadReplyLoader();
      await loader.loadRoot(mockMatrix, roomId, rootId);
      expect(loader.replyIds, ['\$r1:example.com']);

      // Second page: includes a duplicate + a new reply.
      when(mockClient.getRelatingEventsWithRelType(
        roomId,
        rootId,
        RelationshipTypes.thread,
        limit: anyNamed('limit'),
        from: argThat(equals('batch1'), named: 'from'),
      )).thenAnswer((_) async => GetRelatingEventsWithRelTypeResponse(
        chunk: [
          _msgEvent('\$r1:example.com', ts: 200), // duplicate
          _msgEvent('\$r2:example.com', ts: 300), // new
        ],
        nextBatch: null,
      ));

      final loaded = await loader.loadMoreReplies(mockMatrix, roomId, rootId);

      expect(loaded, isTrue);
      // Deduped: r1 not duplicated
      expect(loader.replyIds, ['\$r1:example.com', '\$r2:example.com']);
      expect(loader.hasMore, isFalse);
      loader.dispose();
    });

    test('returns false when hasMore is false (no nextBatch)', () async {
      final rootEvent = Event.fromMatrixEvent(_msgEvent(rootId, ts: 100), mockRoom);
      when(mockRoom.getEventById(rootId))
          .thenAnswer((_) async => rootEvent);
      when(mockClient.getRelatingEventsWithRelType(
        roomId,
        rootId,
        RelationshipTypes.thread,
        limit: anyNamed('limit'),
        from: argThat(isNull, named: 'from'),
      )).thenAnswer((_) async => GetRelatingEventsWithRelTypeResponse(
        chunk: [_msgEvent('\$r1:example.com', ts: 200)],
        nextBatch: null, // no more pages
      ));

      final loader = ThreadReplyLoader();
      await loader.loadRoot(mockMatrix, roomId, rootId);

      final loaded = await loader.loadMoreReplies(mockMatrix, roomId, rootId);

      expect(loaded, isFalse);
      loader.dispose();
    });

    test('returns false when room is null', () async {
      final loader = ThreadReplyLoader();
      // No prior loadRoot → _repliesNextBatch is null → returns false
      final loaded = await loader.loadMoreReplies(mockMatrix, roomId, rootId);

      expect(loaded, isFalse);
      loader.dispose();
    });
  });

  group('ThreadReplyLoader.dispose', () {
    test('resets all state', () async {
      final rootEvent = Event.fromMatrixEvent(_msgEvent(rootId, ts: 100), mockRoom);
      when(mockRoom.getEventById(rootId))
          .thenAnswer((_) async => rootEvent);
      when(mockClient.getRelatingEventsWithRelType(
        roomId,
        rootId,
        RelationshipTypes.thread,
        limit: anyNamed('limit'),
        from: argThat(isNull, named: 'from'),
      )).thenAnswer((_) async => GetRelatingEventsWithRelTypeResponse(
        chunk: [_msgEvent('\$r1:example.com', ts: 200)],
        nextBatch: 'batch1',
      ));

      final loader = ThreadReplyLoader();
      await loader.loadRoot(mockMatrix, roomId, rootId);
      expect(loader.rootEvent, isNotNull);
      expect(loader.hasMore, isTrue);

      loader.dispose();

      expect(loader.rootEvent, isNull);
      expect(loader.replyIds, isEmpty);
      expect(loader.hasMore, isFalse);
      expect(loader.seedEvents, isEmpty);
    });
  });
}
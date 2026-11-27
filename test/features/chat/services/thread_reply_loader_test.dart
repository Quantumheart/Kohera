import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_thread_children_page.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/features/chat/services/thread_reply_loader.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<MessageRepository>()])
import 'thread_reply_loader_test.mocks.dart';

KoheraTimelineEvent _domainEvent(String id, {int ts = 0}) {
  return KoheraTimelineEvent(
    eventId: id,
    senderId: '@alice:example.com',
    type: 'm.room.message',
    messageType: 'm.text',
    body: 'reply $id',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    redacted: false,
    canRedact: false,
    content: const {'body': 'reply', 'msgtype': 'm.text'},
  );
}

void main() {
  late MockMessageRepository messages;

  const roomId = '!room:example.com';
  const rootId = r'$root:example.com';

  setUp(() {
    messages = MockMessageRepository();
  });

  group('ThreadReplyLoader.loadRoot', () {
    test('returns true and populates state when root event found', () async {
      when(messages.fetchEvent(roomId, rootId))
          .thenAnswer((_) async => _domainEvent(rootId, ts: 100));
      when(messages.fetchThreadChildrenPage(roomId, rootId)).thenAnswer(
        (_) async => KoheraThreadChildrenPage(
          events: [_domainEvent(r'$r1:example.com', ts: 200)],
          nextBatch: 'batch1',
        ),
      );

      final loader = ThreadReplyLoader();
      final found = await loader.loadRoot(messages, roomId, rootId);

      expect(found, isTrue);
      expect(loader.rootEvent, isNotNull);
      expect(loader.rootEvent!.eventId, rootId);
      expect(loader.replyIds, [r'$r1:example.com']);
      expect(loader.hasMore, isTrue);
      expect(loader.seedEvents.length, 2);
      expect(loader.seedEvents.first.eventId, rootId);
      loader.dispose();
    });

    test('returns false when root event not found', () async {
      when(messages.fetchEvent(roomId, rootId)).thenAnswer((_) async => null);
      when(messages.fetchThreadChildrenPage(roomId, rootId)).thenAnswer(
        (_) async => const KoheraThreadChildrenPage(events: []),
      );

      final loader = ThreadReplyLoader();
      final found = await loader.loadRoot(messages, roomId, rootId);

      expect(found, isFalse);
      expect(loader.rootEvent, isNull);
      expect(loader.replyIds, isEmpty);
      expect(loader.hasMore, isFalse);
      expect(loader.seedEvents, isEmpty);
      loader.dispose();
    });
  });

  group('ThreadReplyLoader.loadMoreReplies', () {
    test('loads next page and deduplicates by eventId', () async {
      when(messages.fetchEvent(roomId, rootId))
          .thenAnswer((_) async => _domainEvent(rootId, ts: 100));
      when(messages.fetchThreadChildrenPage(roomId, rootId)).thenAnswer(
        (_) async => KoheraThreadChildrenPage(
          events: [_domainEvent(r'$r1:example.com', ts: 200)],
          nextBatch: 'batch1',
        ),
      );

      final loader = ThreadReplyLoader();
      await loader.loadRoot(messages, roomId, rootId);
      expect(loader.replyIds, [r'$r1:example.com']);

      when(messages.fetchThreadChildrenPage(roomId, rootId, from: 'batch1'))
          .thenAnswer(
        (_) async => KoheraThreadChildrenPage(
          events: [
            _domainEvent(r'$r1:example.com', ts: 200),
            _domainEvent(r'$r2:example.com', ts: 300),
          ],
        ),
      );

      final loaded = await loader.loadMoreReplies(messages, roomId, rootId);

      expect(loaded, isTrue);
      expect(loader.replyIds, [r'$r1:example.com', r'$r2:example.com']);
      expect(loader.hasMore, isFalse);
      loader.dispose();
    });

    test('returns false when hasMore is false (no nextBatch)', () async {
      when(messages.fetchEvent(roomId, rootId))
          .thenAnswer((_) async => _domainEvent(rootId, ts: 100));
      when(messages.fetchThreadChildrenPage(roomId, rootId)).thenAnswer(
        (_) async => KoheraThreadChildrenPage(
          events: [_domainEvent(r'$r1:example.com', ts: 200)],
        ),
      );

      final loader = ThreadReplyLoader();
      await loader.loadRoot(messages, roomId, rootId);

      final loaded = await loader.loadMoreReplies(messages, roomId, rootId);

      expect(loaded, isFalse);
      loader.dispose();
    });

    test('returns false before any loadRoot call', () async {
      final loader = ThreadReplyLoader();

      final loaded = await loader.loadMoreReplies(messages, roomId, rootId);

      expect(loaded, isFalse);
      loader.dispose();
    });
  });

  group('ThreadReplyLoader.dispose', () {
    test('resets all state', () async {
      when(messages.fetchEvent(roomId, rootId))
          .thenAnswer((_) async => _domainEvent(rootId, ts: 100));
      when(messages.fetchThreadChildrenPage(roomId, rootId)).thenAnswer(
        (_) async => KoheraThreadChildrenPage(
          events: [_domainEvent(r'$r1:example.com', ts: 200)],
          nextBatch: 'batch1',
        ),
      );

      final loader = ThreadReplyLoader();
      await loader.loadRoot(messages, roomId, rootId);
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

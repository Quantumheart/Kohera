import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_timeline.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<RoomRepository>(),
  MockSpec<MessageRepository>(),
])
import 'message_timeline_controller_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRoomRepository mockRooms;
  late MockMessageRepository mockMessages;
  late MessageTimelineController controller;

  const roomId = '!room:example.com';

  var fragmented = false;
  var canRequest = false;
  var timelineEvents = <KoheraTimelineEvent>[];
  KoheraTimeline? lastTimeline;

  KoheraTimeline buildTimeline() {
    return lastTimeline = KoheraTimeline(
      roomId: roomId,
      events: timelineEvents,
      canRequestHistory: () => canRequest,
      isFragmented: () => fragmented,
      requestHistory: () async {},
    );
  }

  KoheraTimelineEvent domainEvent(
    String id, {
    String senderId = '@alice:example.com',
    DateTime? ts,
    String? relationshipType,
    String? relationshipEventId,
    Map<String, List<String>> aggregated = const {},
  }) {
    return KoheraTimelineEvent(
      eventId: id,
      senderId: senderId,
      type: 'm.room.message',
      messageType: 'm.text',
      body: 'body $id',
      originServerTs: ts ?? DateTime(2026),
      redacted: false,
      canRedact: false,
      content: {'body': 'body $id', 'msgtype': 'm.text'},
      relationshipType: relationshipType,
      relationshipEventId: relationshipEventId,
      aggregatedEventIds: aggregated,
    );
  }

  setUp(() {
    mockRooms = MockRoomRepository();
    mockMessages = MockMessageRepository();
    fragmented = false;
    canRequest = false;
    timelineEvents = [];
    lastTimeline = null;

    when(mockRooms.roomExists(roomId)).thenReturn(true);
    when(mockRooms.userId).thenReturn('@me:example.com');
    when(mockRooms.ignoredUsers).thenReturn([]);
    when(mockRooms.readReceipts(roomId, threadRootId: anyNamed('threadRootId')))
        .thenReturn(const {});
    when(mockRooms.latestOwnThreadReceiptTs(any, any)).thenReturn(0);
    when(mockRooms.isPinned(any, any)).thenReturn(false);
    when(mockRooms.canChangePinnedEvents(any)).thenReturn(false);
    when(mockRooms.notificationCount(roomId)).thenReturn(0);
    when(mockRooms.fullyReadMarkerId(roomId)).thenReturn(null);
    when(
      mockMessages.getTimeline(
        roomId,
        eventContextId: anyNamed('eventContextId'),
      ),
    ).thenAnswer((_) async => buildTimeline());
    when(mockMessages.preDecryptRoomHistory(roomId)).thenAnswer((_) async {});
    when(mockMessages.mediaControllerFor(any, any)).thenReturn(null);

    controller = MessageTimelineController(
      roomRepository: mockRooms,
      messageRepository: mockMessages,
      roomId: roomId,
      sendPublicReadReceipts: false,
    );
  });

  tearDown(() => controller.dispose());

  group('isFragmented', () {
    test('reflects the timeline fragmentation state', () async {
      await controller.init();
      fragmented = true;
      expect(controller.isFragmented, isTrue);

      fragmented = false;
      expect(controller.isFragmented, isFalse);
    });
  });

  group('reloadTimelineAtLive', () {
    test('disposes the old timeline and reloads without eventContextId',
        () async {
      await controller.init();
      final first = lastTimeline!;
      fragmented = true;

      await controller.reloadTimelineAtLive();

      expect(first.isDisposed, isTrue);
      expect(lastTimeline, isNot(same(first)));
      verifyNever(
        mockMessages.getTimeline(
          roomId,
          eventContextId: argThat(isNotNull, named: 'eventContextId'),
        ),
      );
    });
  });

  group('read marker', () {
    setUp(() {
      timelineEvents = [domainEvent(r'$latest')];
      when(mockRooms.notificationCount(roomId)).thenReturn(1);
    });

    tearDown(() {
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    test('marks the room read while the app is in the foreground', () {
      fakeAsync((async) {
        WidgetsBinding.instance
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        unawaited(controller.init());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 2));

        verify(
          mockRooms.markRead(roomId, r'$latest'),
        ).called(1);
      });
    });

    for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
      test('defers the read marker while $state until resumed', () {
        fakeAsync((async) {
          WidgetsBinding.instance
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          unawaited(controller.init());
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 2));
          clearInteractions(mockRooms);

          WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
          lastTimeline!.publish(timelineEvents);
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 5));
          verifyNever(mockRooms.markRead(any, any));

          WidgetsBinding.instance
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 2));
          verify(mockRooms.markRead(any, any)).called(1);
        });
      });
    }

    test('stops observing the app lifecycle after dispose', () {
      fakeAsync((async) {
        final disposable = MessageTimelineController(
          roomRepository: mockRooms,
          messageRepository: mockMessages,
          roomId: roomId,
          sendPublicReadReceipts: false,
        );
        WidgetsBinding.instance
            .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        unawaited(disposable.init());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 2));
        disposable.dispose();

        WidgetsBinding.instance
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 2));

        verifyNever(mockRooms.markRead(any, any));
      });
    });
  });

  group('messages', () {
    test('returns the cached list between reads without updates', () async {
      timelineEvents = [
        domainEvent(r'$a', ts: DateTime(2026, 1, 2)),
        domainEvent(r'$b'),
      ];

      await controller.init();
      final first = controller.messages;
      final second = controller.messages;

      expect(first, hasLength(2));
      expect(identical(first, second), isTrue);
    });

    test('recomputes after a timeline publish', () async {
      timelineEvents = [domainEvent(r'$a')];

      await controller.init();
      final first = controller.messages;

      timelineEvents = [
        KoheraTimelineEvent(
          eventId: r'$a',
          senderId: '@alice:example.com',
          type: 'm.room.message',
          messageType: 'm.text',
          body: 'edited body',
          originServerTs: DateTime(2026),
          redacted: false,
          canRedact: false,
          content: const {'body': 'edited body', 'msgtype': 'm.text'},
        ),
      ];
      lastTimeline!.publish(timelineEvents);
      await Future<void>.delayed(Duration.zero);

      final second = controller.messages;
      expect(identical(first, second), isFalse);
      expect(second[0].message.body, 'edited body');
    });

    test('populates thread info from aggregation', () async {
      final child = domainEvent(
        r'$child',
        ts: DateTime(2026, 1, 3),
        relationshipType: 'm.thread',
        relationshipEventId: r'$root',
      );
      final root = domainEvent(
        r'$root',
        aggregated: const {
          'm.thread': [r'$child'],
        },
      );
      timelineEvents = [child, root];

      await controller.init();
      final messages = controller.messages;

      expect(messages, hasLength(1));
      expect(messages[0].hasThread, isTrue);
      expect(messages[0].threadReplyCount, 1);
      expect(messages[0].threadUnreadCount, 1);
    });
  });
}

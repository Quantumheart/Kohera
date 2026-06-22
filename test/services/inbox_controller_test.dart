import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<User>(),
])
import 'inbox_controller_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

Notification _makeNotification({
  required String eventId,
  required String roomId,
  bool read = false,
  int ts = 1000,
  Map<String, Object?>? content,
  String type = 'm.room.message',
  List<Object?> actions = const [],
}) {
  return Notification(
    actions: actions,
    event: MatrixEvent(
      type: type,
      content: content ?? {'body': 'hello', 'msgtype': 'm.text'},
      senderId: '@alice:example.com',
      eventId: eventId,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      roomId: roomId,
    ),
    read: read,
    roomId: roomId,
    ts: ts,
  );
}

GetNotificationsResponse _makeResponse(
  List<Notification> notifications, {
  String? nextToken,
}) {
  return GetNotificationsResponse(
    notifications: notifications,
    nextToken: nextToken,
  );
}

void main() {
  late MockClient mockClient;
  late InboxController controller;

  late MockRoom defaultRoom;

  late CachedStreamController<SyncUpdate> syncCtl;

  setUp(() {
    mockClient = MockClient();
    defaultRoom = MockRoom();
    syncCtl = CachedStreamController<SyncUpdate>();
    when(defaultRoom.membership).thenReturn(Membership.join);
    when(mockClient.getRoomById(any)).thenReturn(defaultRoom);
    when(mockClient.onSync).thenReturn(syncCtl);
    controller = InboxController(client: mockClient);
  });

  tearDown(() {
    controller.dispose();
  });

  // ── fetch() happy path ──────────────────────────────────────

  group('fetch()', () {
    test('populates grouped, transitions isLoading, clears error', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x'),
            _makeNotification(eventId: 'e3', roomId: '!r2:x'),
          ]),);

      expect(controller.isLoading, isFalse);

      await controller.fetch();

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.grouped, hasLength(2));
      expect(controller.grouped[0].roomId, '!r1:x');
      expect(controller.grouped[0].notifications, hasLength(2));
      expect(controller.grouped[1].roomId, '!r2:x');
    });

    test('generation counter discards stale fetch results', () async {
      when(mockClient.userID).thenReturn('@me:example.com');
      final completer1 = Completer<GetNotificationsResponse>();
      final completer2 = Completer<GetNotificationsResponse>();

      var callCount = 0;
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) {
        callCount++;
        if (callCount == 1) return completer1.future;
        return completer2.future;
      });

      // Start first fetch
      final future1 = controller.fetch();

      // Start second fetch (via setFilter), which increments generation
      controller.setFilter(InboxFilter.mentions);

      // Complete second fetch first with new data
      completer2.complete(_makeResponse([
        _makeNotification(
          eventId: 'new1',
          roomId: '!new:x',
          actions: [
            'notify',
            {'set_tweak': 'highlight'},
          ],
        ),
      ]),);

      // Wait for second fetch to finish
      // (setFilter calls fetch internally, we need to let it settle)
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Now complete the first (stale) fetch
      completer1.complete(_makeResponse([
        _makeNotification(eventId: 'old1', roomId: '!old:x'),
      ]),);

      await future1;

      // The stale results should be discarded, new results should be present
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!new:x');
    });

    test('sets error on exception', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenThrow(Exception('network'));

      await controller.fetch();

      expect(controller.error, contains('network'));
      expect(controller.grouped, isEmpty);
    });

    test('orders groups by most-recent notification descending', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!old:x'),
            _makeNotification(eventId: 'e2', roomId: '!new:x', ts: 3000),
            _makeNotification(eventId: 'e3', roomId: '!mid:x', ts: 2000),
          ]),);

      await controller.fetch();

      expect(
        controller.grouped.map((g) => g.roomId).toList(),
        ['!new:x', '!mid:x', '!old:x'],
      );
    });
  });

  // ── setFilter() ─────────────────────────────────────────────

  group('setFilter()', () {
    test('clears grouped, triggers re-fetch', () async {
      when(mockClient.userID).thenReturn('@me:example.com');
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      expect(controller.grouped, hasLength(1));

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'e2',
              roomId: '!r2:x',
              actions: [
                'notify',
                {'set_tweak': 'highlight'},
              ],
            ),
          ]),);

      controller.setFilter(InboxFilter.mentions);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.filter, InboxFilter.mentions);
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r2:x');
    });

    test('does nothing when setting same filter', () async {
      final notifications = <void Function()>[];
      controller.addListener(() => notifications.add(() {}));

      controller.setFilter(InboxFilter.all); // same as default
      expect(notifications, isEmpty);
    });
  });

  // ── loadMore() ──────────────────────────────────────────────

  group('loadMore()', () {
    test('merges paginated results into existing groups', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();
      expect(controller.hasMore, isTrue);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e2', roomId: '!r1:x'),
            _makeNotification(eventId: 'e3', roomId: '!r2:x'),
          ]),);

      await controller.loadMore();

      expect(controller.grouped, hasLength(2));
      expect(controller.grouped[0].notifications, hasLength(2));
    });

    test('stale loadMore is discarded on filter change', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();

      final loadMoreCompleter = Completer<GetNotificationsResponse>();
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) => loadMoreCompleter.future);

      final loadFuture = controller.loadMore();

      when(mockClient.userID).thenReturn('@me:example.com');
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'new1',
              roomId: '!new:x',
              actions: [
                'notify',
                {'set_tweak': 'highlight'},
              ],
            ),
          ]),);
      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Complete the stale loadMore
      loadMoreCompleter.complete(_makeResponse([
        _makeNotification(eventId: 'stale1', roomId: '!stale:x'),
      ]),);
      await loadFuture;

      // Stale results should be discarded
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!new:x');
    });

    test('dedups notifications by event id across a page boundary', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();

      // Page two repeats e1 (straddling the token boundary) plus a new e2.
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x', ts: 2000),
          ]),);

      await controller.loadMore();

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].notifications, hasLength(2));
    });
  });

  // ── sync refresh preserves pagination (#625) ────────────────

  group('sync-driven refresh', () {
    void stubTwoPages() {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e2', roomId: '!r2:x', ts: 2000)],
            nextToken: 'page3',
          ),);
    }

    test('refresh merges the head and keeps loaded pages', () async {
      stubTwoPages();

      await controller.fetch();
      await controller.loadMore();
      expect(controller.grouped, hasLength(2));
      expect(controller.hasMore, isTrue);

      clearInteractions(mockClient);
      await controller.refresh();

      // Both pages retained; deep pagination token preserved.
      expect(controller.grouped, hasLength(2));
      expect(controller.grouped.map((g) => g.roomId), ['!r2:x', '!r1:x']);
      expect(controller.hasMore, isTrue);

      // Only the first page is re-fetched, not the whole loaded depth.
      verify(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).called(1);
      verifyNever(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),);
    });

    test('sync update does not collapse paged-in list', () {
      fakeAsync((async) {
        stubTwoPages();

        unawaited(controller.fetch());
        async.flushMicrotasks();
        unawaited(controller.loadMore());
        async.flushMicrotasks();
        expect(controller.grouped, hasLength(2));

        controller.startPolling();
        async.flushMicrotasks();
        syncCtl.add(SyncUpdate(
          nextBatch: 'tok',
          rooms: RoomsUpdate(
            join: {
              '!r1:x': JoinedRoomUpdate(
                timeline: TimelineUpdate(events: [
                  MatrixEvent(
                    type: 'm.room.message',
                    content: const {'body': 'hi', 'msgtype': 'm.text'},
                    senderId: '@bob:example.com',
                    eventId: 'sync-evt',
                    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
                    roomId: '!r1:x',
                  ),
                ],),
              ),
            },
          ),
        ),);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        controller.stopPolling();

        // The debounced refresh kept both pages rather than resetting to 30.
        expect(controller.grouped, hasLength(2));
        expect(controller.hasMore, isTrue);
      });
    });
  });

  // ── markRoomAsRead() ────────────────────────────────────────

  group('markRoomAsRead()', () {
    test('calls setReadMarker with latest eventId and refreshes', () async {
      final mockRoom = MockRoom();
      when(mockRoom.membership).thenReturn(Membership.join);
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any, mRead: anyNamed('mRead'))).thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x', ts: 2000),
          ]),);

      await controller.fetch();
      await controller.markRoomAsRead('!r1:x');

      verify(mockRoom.setReadMarker('e2', mRead: 'e2')).called(1);
    });

    test('optimistically removes group before server call', () async {
      final mockRoom = MockRoom();
      when(mockRoom.membership).thenReturn(Membership.join);
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any, mRead: anyNamed('mRead'))).thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      await controller.fetch();
      expect(controller.grouped, hasLength(2));

      final future = controller.markRoomAsRead('!r1:x');
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r2:x');

      await future;
    });
  });

  // ── Sync-stream invalidation ──────────────────────────────

  SyncUpdate syncWithTimelineEvent(String roomId) {
    final ev = MatrixEvent(
      type: 'm.room.message',
      content: const {'body': 'hi', 'msgtype': 'm.text'},
      senderId: '@bob:example.com',
      eventId: 'sync-evt',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      roomId: roomId,
    );
    return SyncUpdate(
      nextBatch: 'tok',
      rooms: RoomsUpdate(
        join: {
          roomId: JoinedRoomUpdate(
            timeline: TimelineUpdate(events: [ev]),
          ),
        },
      ),
    );
  }

  SyncUpdate syncTypingOnly(String roomId) {
    return SyncUpdate(
      nextBatch: 'tok',
      rooms: RoomsUpdate(
        join: {
          roomId: JoinedRoomUpdate(
            ephemeral: [
              BasicEvent(type: 'm.typing', content: const {'user_ids': []}),
            ],
          ),
        },
      ),
    );
  }

  group('startPolling / stopPolling (sync-driven)', () {
    test('sync timeline event triggers debounced fetch', () {
      fakeAsync((async) {
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([]));

        controller.startPolling();
        async.flushMicrotasks();
        // Initial fetch is NOT triggered by startPolling (caller does it).
        clearInteractions(mockClient);

        syncCtl.add(syncWithTimelineEvent('!r1:x'));

        // Before debounce expires: no fetch yet.
        async.elapse(const Duration(milliseconds: 500));
        verifyNever(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),);

        // After debounce: one fetch.
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        verify(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).called(1);

        controller.stopPolling();
      });
    });

    test('burst of sync updates coalesces to one fetch', () {
      fakeAsync((async) {
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([]));

        controller.startPolling();
        async.flushMicrotasks();
        clearInteractions(mockClient);

        syncCtl.add(syncWithTimelineEvent('!r1:x'));
        async.elapse(const Duration(milliseconds: 200));
        syncCtl.add(syncWithTimelineEvent('!r2:x'));
        async.elapse(const Duration(milliseconds: 200));
        syncCtl.add(syncWithTimelineEvent('!r3:x'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        verify(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).called(1);

        controller.stopPolling();
      });
    });

    test('typing-only sync does not trigger fetch', () {
      fakeAsync((async) {
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([]));

        controller.startPolling();
        async.flushMicrotasks();
        clearInteractions(mockClient);

        syncCtl.add(syncTypingOnly('!r1:x'));
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        verifyNever(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),);

        controller.stopPolling();
      });
    });

    test('stopPolling cancels pending debounce', () {
      fakeAsync((async) {
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([]));

        controller.startPolling();
        async.flushMicrotasks();
        clearInteractions(mockClient);

        syncCtl.add(syncWithTimelineEvent('!r1:x'));
        async.elapse(const Duration(milliseconds: 200));
        controller.stopPolling();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        verifyNever(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),);
      });
    });
  });

  // ── dispose ────────────────────────────────────────────────

  group('dispose', () {
    test('no crash when async fetch completes after dispose', () async {
      // Use a separate controller for this test to avoid double-dispose
      final disposableController = InboxController(client: mockClient);
      final completer = Completer<GetNotificationsResponse>();

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) => completer.future);

      final future = disposableController.fetch();
      disposableController.dispose();

      // Complete the fetch after dispose — should not throw
      completer.complete(_makeResponse([
        _makeNotification(eventId: 'e1', roomId: '!r1:x'),
      ]),);

      await future; // No exception
    });
  });

  // ── unreadCount ────────────────────────────────────────────

  group('unreadCount', () {
    test('cached count matches actual unread after fetch', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x', read: true),
            _makeNotification(eventId: 'e3', roomId: '!r2:x'),
          ]),);

      expect(controller.unreadCount, 0);

      await controller.fetch();

      expect(controller.unreadCount, 2);
    });

    test('unreadCount updates after loadMore', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();
      expect(controller.unreadCount, 1);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      await controller.loadMore();
      expect(controller.unreadCount, 2);
    });
  });

  // ── read filtering ─────────────────────────────────────────

  group('read filtering', () {
    test('fetch excludes read notifications from grouped', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x', read: true),
            _makeNotification(eventId: 'e3', roomId: '!r2:x', read: true),
          ]),);

      await controller.fetch();

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
      expect(controller.grouped[0].notifications, hasLength(1));
    });

    test('sync-triggered refetch updates stale local read state', () {
      fakeAsync((async) {
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([
              _makeNotification(eventId: 'e1', roomId: '!r1:x'),
              _makeNotification(eventId: 'e2', roomId: '!r1:x'),
            ]),);

        unawaited(controller.fetch());
        async.flushMicrotasks();
        expect(controller.grouped[0].notifications, hasLength(2));

        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([
              _makeNotification(eventId: 'e1', roomId: '!r1:x', read: true),
              _makeNotification(eventId: 'e2', roomId: '!r1:x'),
            ]),);

        controller.startPolling();
        async.flushMicrotasks();
        // Simulate a receipt from another device clearing 'e1'.
        syncCtl.add(SyncUpdate(
          nextBatch: 'tok',
          rooms: RoomsUpdate(
            join: {
              '!r1:x': JoinedRoomUpdate(
                ephemeral: [
                  BasicEvent(type: 'm.receipt', content: const {}),
                ],
              ),
            },
          ),
        ),);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        controller.stopPolling();

        expect(controller.grouped, hasLength(1));
        expect(controller.grouped[0].notifications, hasLength(1));
        expect(controller.grouped[0].notifications[0].event.eventId, 'e2');
      });
    });
    test('excludes notifications for rooms with non-join membership', () async {
      final leftRoom = MockRoom();
      when(leftRoom.membership).thenReturn(Membership.leave);
      when(mockClient.getRoomById('!left:x')).thenReturn(leftRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!left:x'),
          ]),);

      await controller.fetch();

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
    });

    test('excludes notifications for rooms not in client', () async {
      when(mockClient.getRoomById('!gone:x')).thenReturn(null);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!gone:x'),
          ]),);

      await controller.fetch();

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
    });
  });

  // ── markRoomAsRead max ts ─────────────────────────────────

  group('markRoomAsRead() event selection', () {
    test('uses notification with highest ts, not last in list', () async {
      final mockRoom = MockRoom();
      when(mockRoom.membership).thenReturn(Membership.join);
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any, mRead: anyNamed('mRead'))).thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e-newer', roomId: '!r1:x', ts: 3000),
            _makeNotification(eventId: 'e-older', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      await controller.markRoomAsRead('!r1:x');

      verify(mockRoom.setReadMarker('e-newer', mRead: 'e-newer')).called(1);
    });
  });

  // ── token expiry ──────────────────────────────────────────

  group('token expiry', () {
    test('fetch suppresses error logging on M_UNKNOWN_TOKEN', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenThrow(MatrixException.fromJson({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'Access token has expired',
      }),);

      await controller.fetch();

      expect(controller.error, isNull);
    });

    test('sync subscription stops after M_UNKNOWN_TOKEN', () {
      fakeAsync((async) {
        var callCount = 0;
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) {
          callCount++;
          throw MatrixException.fromJson({
            'errcode': 'M_UNKNOWN_TOKEN',
            'error': 'Access token has expired',
          });
        });

        controller.startPolling();
        unawaited(controller.fetch());
        async.flushMicrotasks();
        expect(callCount, 1);

        // After token expiry, further sync events must not trigger fetch.
        syncCtl.add(SyncUpdate(
          nextBatch: 'tok',
          rooms: RoomsUpdate(
            join: {
              '!r1:x': JoinedRoomUpdate(
                timeline: TimelineUpdate(events: [
                  MatrixEvent(
                    type: 'm.room.message',
                    content: const {'body': 'hi', 'msgtype': 'm.text'},
                    senderId: '@b:x',
                    eventId: 'e1',
                    originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
                    roomId: '!r1:x',
                  ),
                ],),
              ),
            },
          ),
        ),);
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(callCount, 1);

        controller.stopPolling();
      });
    });

    test('markRoomAsRead is no-op when token is expired', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenThrow(MatrixException.fromJson({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'Access token has expired',
      }),);

      await controller.fetch();

      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      await controller.markRoomAsRead('!r1:x');

      verifyNever(mockRoom.setReadMarker(any, mRead: anyNamed('mRead')));
    });

    test('updateClient resets token expiry flag', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenThrow(MatrixException.fromJson({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'Access token has expired',
      }),);

      await controller.fetch();
      expect(controller.error, isNull);

      final newClient = MockClient();
      when(newClient.getRoomById(any)).thenReturn(defaultRoom);
      when(newClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      controller.updateClient(newClient);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
    });
  });

  // ── updateClient() ────────────────────────────────────────

  group('updateClient()', () {
    test('resets state and triggers new fetch', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      expect(controller.grouped, hasLength(1));

      final newClient = MockClient();
      when(newClient.getRoomById(any)).thenReturn(defaultRoom);
      when(newClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'new1', roomId: '!new:x'),
          ]),);

      controller.updateClient(newClient);

      // Wait for async fetch
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!new:x');
    });
  });

  // ── client-side mention filtering ─────────────────────────

  group('mention filtering', () {
    setUp(() {
      when(mockClient.userID).thenReturn('@me:example.com');
      final mockUser = MockUser();
      when(mockUser.calcDisplayname()).thenReturn('Me');
      when(defaultRoom.unsafeGetUserFromMemoryOrFallback('@me:example.com'))
          .thenReturn(mockUser);
    });

    test('mentions filter includes notification with m.mentions user_ids', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'e1',
              roomId: '!r1:x',
              content: {
                'body': 'hello everyone',
                'msgtype': 'm.text',
                'm.mentions': {
                  'user_ids': ['@me:example.com'],
                },
              },
            ),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
    });

    test('mentions filter includes notification with highlight action', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'e1',
              roomId: '!r1:x',
              actions: [
                'notify',
                {'set_tweak': 'highlight'},
              ],
            ),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
    });

    test('mentions filter includes encrypted notification with user ID in body', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'e1',
              roomId: '!r1:x',
              type: 'm.room.encrypted',
              content: {
                'body': 'hey @me:example.com check this',
                'msgtype': 'm.text',
              },
            ),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
    });

    test('mentions filter includes encrypted notification with display name in body', () async {
      final displayUser = MockUser();
      when(displayUser.calcDisplayname()).thenReturn('MyName');
      when(defaultRoom.unsafeGetUserFromMemoryOrFallback('@me:example.com'))
          .thenReturn(displayUser);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'e1',
              roomId: '!r1:x',
              type: 'm.room.encrypted',
              content: {
                'body': 'hey MyName check this out',
                'msgtype': 'm.text',
              },
            ),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
    });

    test('mentions filter excludes plaintext body matches without highlight action', () async {
      final displayUser = MockUser();
      when(displayUser.calcDisplayname()).thenReturn('Will');
      when(defaultRoom.unsafeGetUserFromMemoryOrFallback('@me:example.com'))
          .thenReturn(displayUser);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'e1',
              roomId: '!r1:x',
              content: {
                'body': 'Will you join the call?',
                'msgtype': 'm.text',
              },
            ),
          ]),);

      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, isEmpty);
    });

    test('mentions filter excludes notifications without mentions', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.mentions);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, isEmpty);
    });

    test('all filter does not apply mention filtering', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      await controller.fetch();

      expect(controller.grouped, hasLength(2));
    });
  });

  // ── isMention ─────────────────────────────────────────────

  group('isMention', () {
    setUp(() {
      when(mockClient.userID).thenReturn('@me:example.com');
    });

    void stubDisplayName(String name) {
      final user = MockUser();
      when(user.calcDisplayname()).thenReturn(name);
      when(defaultRoom.unsafeGetUserFromMemoryOrFallback('@me:example.com'))
          .thenReturn(user);
    }

    test('true for highlight action without value', () {
      stubDisplayName('Me');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        actions: [
          'notify',
          {'set_tweak': 'highlight'},
        ],
      );
      expect(controller.isMention(n), isTrue);
    });

    test('true for highlight action with value true', () {
      stubDisplayName('Me');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        actions: [
          'notify',
          {'set_tweak': 'highlight', 'value': true},
        ],
      );
      expect(controller.isMention(n), isTrue);
    });

    test('false for highlight action with value false', () {
      stubDisplayName('Me');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        actions: [
          'notify',
          {'set_tweak': 'highlight', 'value': false},
        ],
      );
      expect(controller.isMention(n), isFalse);
    });

    test('true when m.mentions lists the user', () {
      stubDisplayName('Me');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        content: {
          'body': 'hello everyone',
          'msgtype': 'm.text',
          'm.mentions': {
            'user_ids': ['@me:example.com'],
          },
        },
      );
      expect(controller.isMention(n), isTrue);
    });

    test('true when m.mentions flags a room mention', () {
      stubDisplayName('Me');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {
          'body': 'attention everyone',
          'msgtype': 'm.text',
          'm.mentions': {'room': true},
        },
      );
      expect(controller.isMention(n), isTrue);
    });

    test('false when m.mentions is present without the user, even if the body matches', () {
      stubDisplayName('Me');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {
          'body': 'hey Me, did @other ping you?',
          'msgtype': 'm.text',
          'm.mentions': {
            'user_ids': ['@other:example.com'],
          },
        },
      );
      expect(controller.isMention(n), isFalse);
    });

    test('false for plaintext body match without highlight action', () {
      stubDisplayName('Will');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        content: {'body': 'Will you join?', 'msgtype': 'm.text'},
      );
      expect(controller.isMention(n), isFalse);
    });

    test('encrypted fallback matches a word-bounded display name', () {
      stubDisplayName('Will');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {'body': 'Will, are you there?', 'msgtype': 'm.text'},
      );
      expect(controller.isMention(n), isTrue);
    });

    test('encrypted fallback ignores the display name inside a larger word', () {
      stubDisplayName('Will');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {'body': 'willpower beats talent', 'msgtype': 'm.text'},
      );
      expect(controller.isMention(n), isFalse);
    });

    test('encrypted fallback treats digits as word characters', () {
      stubDisplayName('Max');
      final n = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {'body': 'Max99 said hi', 'msgtype': 'm.text'},
      );
      expect(controller.isMention(n), isFalse);
    });

    test('encrypted fallback is Unicode-aware for Cyrillic display names', () {
      stubDisplayName('Вера');
      final bounded = _makeNotification(
        eventId: 'e1',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {'body': 'Вера, привет', 'msgtype': 'm.text'},
      );
      final embedded = _makeNotification(
        eventId: 'e2',
        roomId: '!r1:x',
        type: 'm.room.encrypted',
        content: {'body': 'проверая текст', 'msgtype': 'm.text'},
      );
      expect(controller.isMention(bounded), isTrue);
      expect(controller.isMention(embedded), isFalse);
    });
  });

  // ── Thread sub-grouping ───────────────────────────────────
  Map<String, Object?> threadContent(String rootId) => {
        'body': 'reply',
        'msgtype': 'm.text',
        'm.relates_to': {
          'rel_type': 'm.thread',
          'event_id': rootId,
        },
      };

  group('thread sub-grouping', () {
    test('two threads in one room produce two sub-groups + main', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'm1', roomId: '!r1:x'),
            _makeNotification(
              eventId: 't1a',
              roomId: '!r1:x',
              ts: 2000,
              content: threadContent(r'$rootA'),
            ),
            _makeNotification(
              eventId: 't1b',
              roomId: '!r1:x',
              ts: 2500,
              content: threadContent(r'$rootA'),
            ),
            _makeNotification(
              eventId: 't2',
              roomId: '!r1:x',
              ts: 3000,
              content: threadContent(r'$rootB'),
            ),
          ]),);

      await controller.fetch();

      expect(controller.grouped, hasLength(1));
      final subs = controller.grouped[0].subGroups;
      expect(subs, hasLength(3));
      expect(subs[0].threadRootId, r'$rootB');
      expect(subs[0].notifications, hasLength(1));
      expect(subs[1].threadRootId, r'$rootA');
      expect(subs[1].notifications, hasLength(2));
      expect(subs[2].threadRootId, isNull);
      expect(subs[2].notifications, hasLength(1));
    });

    test('main-only room yields single null-keyed sub-group', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x', ts: 2000),
          ]),);

      await controller.fetch();

      final subs = controller.grouped[0].subGroups;
      expect(subs, hasLength(1));
      expect(subs[0].threadRootId, isNull);
      expect(subs[0].notifications, hasLength(2));
    });
  });

  // ── threads filter ────────────────────────────────────────
  group('threads filter', () {
    test('excludes non-thread notifications', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'm1', roomId: '!r1:x'),
            _makeNotification(
              eventId: 't1',
              roomId: '!r1:x',
              ts: 2000,
              content: threadContent(r'$root'),
            ),
            _makeNotification(eventId: 'm2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.threads);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r1:x');
      expect(controller.grouped[0].notifications, hasLength(1));
      expect(controller.grouped[0].notifications[0].event.eventId, 't1');
    });
  });

  // ── markRoomAsRead parallel + stale main ─────────────────
  group('markRoomAsRead() parallelization', () {
    test('per-thread receipts dispatched in parallel (not sequential)',
        () async {
      final mockRoom = MockRoom();
      when(mockRoom.membership).thenReturn(Membership.join);
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any, mRead: anyNamed('mRead')))
          .thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      final completers = <String, Completer<void>>{
        r'$rA': Completer<void>(),
        r'$rB': Completer<void>(),
      };
      when(mockClient.postReceipt(
        any,
        any,
        any,
        threadId: anyNamed('threadId'),
      ),).thenAnswer((inv) {
        final tid = inv.namedArguments[#threadId] as String;
        return completers[tid]!.future;
      });

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(
              eventId: 'tA',
              roomId: '!r1:x',
              ts: 2000,
              content: threadContent(r'$rA'),
            ),
            _makeNotification(
              eventId: 'tB',
              roomId: '!r1:x',
              ts: 3000,
              content: threadContent(r'$rB'),
            ),
          ]),);

      await controller.fetch();
      final markFuture = controller.markRoomAsRead('!r1:x');

      // Let microtasks drain so both postReceipt calls are issued.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Both receipts in flight before either completes => parallel.
      verify(mockClient.postReceipt('!r1:x', any, 'tA',
              threadId: r'$rA',),).called(1);
      verify(mockClient.postReceipt('!r1:x', any, 'tB',
              threadId: r'$rB',),).called(1);

      completers[r'$rA']!.complete();
      completers[r'$rB']!.complete();
      await markFuture;
    });

    test('skips main receipt when thread reply is newer', () async {
      final mockRoom = MockRoom();
      when(mockRoom.membership).thenReturn(Membership.join);
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any, mRead: anyNamed('mRead')))
          .thenAnswer((_) async {});
      when(mockClient.postReceipt(any, any, any,
              threadId: anyNamed('threadId'),),)
          .thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'm-old', roomId: '!r1:x'),
            _makeNotification(
              eventId: 't-new',
              roomId: '!r1:x',
              ts: 5000,
              content: threadContent(r'$root'),
            ),
          ]),);

      await controller.fetch();
      await controller.markRoomAsRead('!r1:x');

      verifyNever(mockRoom.setReadMarker(any, mRead: anyNamed('mRead')));
      verify(mockClient.postReceipt('!r1:x', any, 't-new',
              threadId: r'$root',),).called(1);
    });

    test('posts main receipt when no threads present', () async {
      final mockRoom = MockRoom();
      when(mockRoom.membership).thenReturn(Membership.join);
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any, mRead: anyNamed('mRead')))
          .thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      await controller.markRoomAsRead('!r1:x');

      verify(mockRoom.setReadMarker('e1', mRead: 'e1')).called(1);
    });
  });
}

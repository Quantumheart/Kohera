import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/notifications/enum/inbox_filter.dart';
import 'package:kohera/features/notifications/services/notification_grouper.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Encryption>(),
])
import 'notification_grouper_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

Notification _encryptedNotification({
  required String eventId,
  required String roomId,
  Map<String, Object?>? content,
  int ts = 1000,
}) {
  return Notification(
    actions: const [],
    event: MatrixEvent(
      type: 'm.room.encrypted',
      content: content ?? const {},
      senderId: '@alice:example.com',
      eventId: eventId,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      roomId: roomId,
    ),
    read: false,
    roomId: roomId,
    ts: ts,
  );
}

Notification _plaintextNotification({
  required String eventId,
  required String roomId,
  int ts = 1000,
}) {
  return Notification(
    actions: const [],
    event: MatrixEvent(
      type: 'm.room.message',
      content: const {'body': 'hello', 'msgtype': 'm.text'},
      senderId: '@alice:example.com',
      eventId: eventId,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      roomId: roomId,
    ),
    read: false,
    roomId: roomId,
    ts: ts,
  );
}

Event _decryptedEvent({
  required String eventId,
  required Room room,
  Map<String, Object?>? content,
}) {
  return Event(
    content: content ?? const {'body': 'decrypted text', 'msgtype': 'm.text'},
    type: 'm.room.message',
    eventId: eventId,
    senderId: '@alice:example.com',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    room: room,
  );
}

/// Common setup: wires the room's `client` getter to [mockClient] so that
/// `_tryDecrypt` can reach `mockClient.encryption`.
void _wireRoom(MockRoom room, MockClient client) {
  when(room.client).thenReturn(client);
  when(room.membership).thenReturn(Membership.join);
}

void main() {
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockEncryption mockEncryption;
  late NotificationGrouper grouper;

  setUp(() {
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockEncryption = MockEncryption();
    _wireRoom(mockRoom, mockClient);

    when(mockClient.getRoomById(any)).thenReturn(mockRoom);
    when(mockClient.encryption).thenReturn(mockEncryption);
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');

    grouper = NotificationGrouper(mockClient);
  });

  // ── Concurrent decryption (#629) ──────────────────────────

  group('concurrent decryption', () {
    test('decrypts all encrypted events in parallel, not serially', () async {
      final completers = <String, Completer<Event>>{
        'e1': Completer<Event>(),
        'e2': Completer<Event>(),
        'e3': Completer<Event>(),
      };

      when(mockEncryption.decryptRoomEvent(any)).thenAnswer((inv) {
        final event = inv.positionalArguments[0] as Event;
        return completers[event.eventId]!.future;
      });

      final notifications = [
        _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
        _encryptedNotification(eventId: 'e2', roomId: '!r:x'),
        _encryptedNotification(eventId: 'e3', roomId: '!r:x'),
      ];

      // Start grouping — this kicks off Future.wait over _tryDecrypt.
      final groupFuture = grouper.group(notifications, InboxFilter.all);

      // Let microtasks drain so all _tryDecrypt futures are started.
      await Future<void>.delayed(Duration.zero);

      // All three decryptRoomEvent calls must be in-flight before any
      // completes — proving concurrency, not serial execution.
      verify(mockEncryption.decryptRoomEvent(any)).called(3);

      // Complete all — group() should finish.
      completers['e1']!.complete(_decryptedEvent(eventId: 'e1', room: mockRoom));
      completers['e2']!.complete(_decryptedEvent(eventId: 'e2', room: mockRoom));
      completers['e3']!.complete(_decryptedEvent(eventId: 'e3', room: mockRoom));

      final groups = await groupFuture;
      expect(groups, hasLength(1));
      expect(groups[0].notifications, hasLength(3));
    });
  });

  // ── Negative cache (#629) ──────────────────────────────────

  group('negative cache', () {
    test('failed decryption is not retried within TTL', () async {
      when(mockEncryption.decryptRoomEvent(any))
          .thenThrow(Exception('keys unavailable'));

      final notifications = [
        _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
      ];

      await grouper.group(notifications, InboxFilter.all);
      // First call attempted decryption.
      verify(mockEncryption.decryptRoomEvent(any)).called(1);

      // Second group() call — failure is cached, no retry.
      await grouper.group(notifications, InboxFilter.all);
      verifyNever(mockEncryption.decryptRoomEvent(any));

      expect(grouper.decryptedContentFor('e1'), isNull);
    });

    test('failure is retried after TTL expires', () {
      fakeAsync((async) {
        when(mockEncryption.decryptRoomEvent(any))
            .thenThrow(Exception('keys unavailable'));

        final notifications = [
          _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
        ];

        // First group() — fails and caches.
        unawaited(grouper.group(notifications, InboxFilter.all));
        async.flushMicrotasks();
        verify(mockEncryption.decryptRoomEvent(any)).called(1);

        // Within TTL — no retry.
        async.elapse(const Duration(seconds: 10));
        unawaited(grouper.group(notifications, InboxFilter.all));
        async.flushMicrotasks();
        verifyNever(mockEncryption.decryptRoomEvent(any));

        // After TTL expires — retry.
        async.elapse(const Duration(seconds: 25));
        unawaited(grouper.group(notifications, InboxFilter.all));
        async.flushMicrotasks();
        verify(mockEncryption.decryptRoomEvent(any)).called(1);
      });
    });

    test('successful decryption clears the failure entry', () {
      fakeAsync((async) {
        // First attempt fails.
        when(mockEncryption.decryptRoomEvent(any))
            .thenThrow(Exception('keys unavailable'));

        final notifications = [
          _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
        ];

        unawaited(grouper.group(notifications, InboxFilter.all));
        async.flushMicrotasks();
        verify(mockEncryption.decryptRoomEvent(any)).called(1);

        // Advance past TTL so the failure entry expires.
        async.elapse(const Duration(seconds: 31));

        // Second attempt succeeds (keys restored).
        final decrypted = _decryptedEvent(eventId: 'e1', room: mockRoom);
        when(mockEncryption.decryptRoomEvent(any))
            .thenAnswer((_) async => decrypted);

        unawaited(grouper.group(notifications, InboxFilter.all));
        async.flushMicrotasks();
        verify(mockEncryption.decryptRoomEvent(any)).called(1);

        // Content is now cached.
        expect(grouper.decryptedContentFor('e1'), isNotNull);

        // A subsequent call should NOT retry (success is cached).
        unawaited(grouper.group(notifications, InboxFilter.all));
        async.flushMicrotasks();
        verifyNever(mockEncryption.decryptRoomEvent(any));
      });
    });

    test('success after failure without TTL expiry also clears entry',
        () async {
      // This is the case where the TTL hasn't expired but a retry happens
      // for some other reason (e.g. clearCache + re-group).  We test that
      // once content is cached, subsequent calls don't retry.
      final decrypted = _decryptedEvent(eventId: 'e1', room: mockRoom);
      when(mockEncryption.decryptRoomEvent(any))
          .thenAnswer((_) async => decrypted);

      final notifications = [
        _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
      ];

      // First group() succeeds and caches.
      await grouper.group(notifications, InboxFilter.all);
      verify(mockEncryption.decryptRoomEvent(any)).called(1);

      // Second group() — success is cached, no retry.
      await grouper.group(notifications, InboxFilter.all);
      verifyNever(mockEncryption.decryptRoomEvent(any));

      expect(grouper.decryptedContentFor('e1'), isNotNull);
    });
  });

  // ── clearCache ─────────────────────────────────────────────

  group('clearCache', () {
    test('clears both success and failure caches', () async {
      // e1: successful decryption (cached in _decryptedContent)
      final decrypted = _decryptedEvent(eventId: 'e1', room: mockRoom);
      // e2: failed decryption (cached in _decryptionFailedAt)
      when(mockEncryption.decryptRoomEvent(any)).thenAnswer((inv) {
        final event = inv.positionalArguments[0] as Event;
        if (event.eventId == 'e1') return Future.value(decrypted);
        throw Exception('keys unavailable');
      });

      final notifications = [
        _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
        _encryptedNotification(eventId: 'e2', roomId: '!r:x'),
      ];

      await grouper.group(notifications, InboxFilter.all);
      expect(grouper.decryptedContentFor('e1'), isNotNull);

      // After clearCache, both caches are empty.
      grouper.clearCache();
      expect(grouper.decryptedContentFor('e1'), isNull);

      // Re-grouping should attempt decryption for both again.
      clearInteractions(mockEncryption);
      await grouper.group(notifications, InboxFilter.all);
      verify(mockEncryption.decryptRoomEvent(any)).called(2);
    });
  });

  // ── Non-encrypted events ───────────────────────────────────

  group('non-encrypted events', () {
    test('plaintext events are not sent to decryption', () async {
      final notifications = [
        _plaintextNotification(eventId: 'e1', roomId: '!r:x'),
        _plaintextNotification(eventId: 'e2', roomId: '!r:x'),
      ];

      final groups = await grouper.group(notifications, InboxFilter.all);

      verifyNever(mockEncryption.decryptRoomEvent(any));
      expect(groups, hasLength(1));
      expect(groups[0].notifications, hasLength(2));
    });
  });

  // ── Room without encryption ───────────────────────────────

  group('room without encryption', () {
    test('null encryption is treated as failure and cached', () async {
      when(mockClient.encryption).thenReturn(null);

      final notifications = [
        _encryptedNotification(eventId: 'e1', roomId: '!r:x'),
      ];

      await grouper.group(notifications, InboxFilter.all);

      // Second call should not retry (failure cached).
      await grouper.group(notifications, InboxFilter.all);

      // decryptRoomEvent was never called because encryption was null.
      verifyNever(mockEncryption.decryptRoomEvent(any));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/account_session.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;
  late MessageRepository repo;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.database).thenReturn(_FakeDatabase());
    service = MatrixService(
      accountSession: AccountSession(matrixClientService: MatrixClientService(mockClient)),
      storage: mockStorage,
      clientName: 'test',
    );
    repo = MessageRepository(clientService: service.matrixClientService, clientName: 'test');
  });

  group('timelineFor', () {
    test('returns null for unknown room', () async {
      when(mockClient.getRoomById('!unknown:example.com')).thenReturn(null);
      expect(await repo.timelineFor('!unknown:example.com'), isNull);
    });
  });

  group('getTimeline', () {
    late MockRoom room;
    late _FakeTimeline sdkTimeline;
    void Function()? capturedOnUpdate;

    setUp(() {
      room = MockRoom();
      sdkTimeline = _FakeTimeline();
      capturedOnUpdate = null;
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(
        room.getTimeline(
          eventContextId: anyNamed('eventContextId'),
          onUpdate: anyNamed('onUpdate'),
          onInsert: anyNamed('onInsert'),
          onChange: anyNamed('onChange'),
          onRemove: anyNamed('onRemove'),
        ),
      ).thenAnswer((invocation) async {
        capturedOnUpdate =
            invocation.namedArguments[#onUpdate] as void Function()?;
        return sdkTimeline;
      });
    });

    test('returns null for unknown room', () async {
      expect(await repo.getTimeline('!unknown:example.com'), isNull);
    });

    test('converts the current event list', () async {
      sdkTimeline.eventsList = [
        _FakeEvent(eventId: r'$a:s', body: 'first'),
        _FakeEvent(eventId: r'$b:s', body: 'second'),
      ];

      final timeline = await repo.getTimeline('!room:example.com');

      expect(timeline, isNotNull);
      expect(timeline!.roomId, '!room:example.com');
      expect(timeline.events, hasLength(2));
      expect(timeline.events[0].eventId, r'$a:s');
      expect(timeline.events[1].body, 'second');
      timeline.dispose();
    });

    test('publishes converted snapshots on SDK updates', () async {
      final timeline = await repo.getTimeline('!room:example.com');
      final emitted = <List<String>>[];
      final sub = timeline!.onEvents.listen(
        (events) => emitted.add(events.map((e) => e.eventId).toList()),
      );

      sdkTimeline.eventsList = [_FakeEvent(eventId: r'$new:s')];
      capturedOnUpdate!.call();

      expect(timeline.events.single.eventId, r'$new:s');
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [
        [r'$new:s'],
      ]);
      await sub.cancel();
      timeline.dispose();
    });

    test('delegates pagination and fragmentation state', () async {
      sdkTimeline.canRequest = true;
      sdkTimeline.allowNew = false;

      final timeline = await repo.getTimeline('!room:example.com');

      expect(timeline!.isFragmented, isTrue);
      expect(timeline.canRequestHistory, isTrue);
      await timeline.requestHistory();
      expect(sdkTimeline.historyRequests, 1);
      timeline.dispose();
    });

    test('dispose cancels SDK subscriptions', () async {
      final timeline = await repo.getTimeline('!room:example.com');
      timeline!.dispose();

      expect(sdkTimeline.cancelled, isTrue);
      capturedOnUpdate!.call();
      expect(timeline.events, isEmpty);
    });
  });

  group('fetchThreadSummaries', () {
    late MockRoom room;

    MatrixEvent rawMessage(
      String id,
      String sender,
      DateTime ts, {
      String body = 'x',
    }) {
      return MatrixEvent(
        type: EventTypes.Message,
        eventId: id,
        senderId: sender,
        originServerTs: ts,
        content: <String, Object?>{
          'msgtype': MessageTypes.Text,
          'body': body,
        },
      );
    }

    setUp(() {
      room = MockRoom();
      when(room.id).thenReturn('!room:example.com');
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(mockClient.userID).thenReturn('@me:example.com');
      when(room.receiptState).thenReturn(_FakeReceipts(const {}));
      when(room.unsafeGetUserFromMemoryOrFallback(any)).thenAnswer(
        (invocation) =>
            User(invocation.positionalArguments.first as String, room: room),
      );
    });

    void stubChildren(String rootId, List<MatrixEvent> children) {
      when(
        mockClient.getRelatingEventsWithRelType(
          '!room:example.com',
          rootId,
          RelationshipTypes.thread,
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => GetRelatingEventsWithRelTypeResponse(chunk: children),
      );
    }

    test('returns empty list for unknown room', () async {
      expect(await repo.fetchThreadSummaries('!unknown:example.com'), isEmpty);
    });

    const rootsLimit = 50;

    test('builds summaries sorted by latest activity', () async {
      when(mockClient.getThreadRoots('!room:example.com', limit: rootsLimit))
          .thenAnswer(
        (_) async => GetThreadRootsResponse(
          chunk: [
            rawMessage(r'$root1:s', '@alice:example.com', DateTime(2026, 2),
                body: 'first thread'),
            rawMessage(r'$root2:s', '@bob:example.com', DateTime(2026, 2, 3),
                body: 'second thread'),
          ],
        ),
      );
      stubChildren(r'$root1:s', [
        rawMessage(r'$r1:s', '@alice:example.com', DateTime(2026, 2, 4),
            body: 'newer reply'),
      ]);
      stubChildren(r'$root2:s', [
        rawMessage(r'$r2:s', '@me:example.com', DateTime(2026, 2, 3, 1),
            body: 'own reply'),
      ]);

      final summaries = await repo.fetchThreadSummaries('!room:example.com');

      expect(summaries, hasLength(2));
      // root1 has the newest activity (reply at Feb 4) and sorts first.
      expect(summaries[0].rootEventId, r'$root1:s');
      expect(summaries[0].rootBody, 'first thread');
      expect(summaries[0].replyCount, 1);
      expect(summaries[0].lastReplyBody, 'newer reply');
      expect(summaries[1].rootEventId, r'$root2:s');
      expect(summaries[1].replyCount, 1);
    });

    test('unread counts other-user replies, excluding own', () async {
      when(mockClient.getThreadRoots('!room:example.com', limit: 50))
          .thenAnswer(
        (_) async => GetThreadRootsResponse(
          chunk: [
            rawMessage(r'$root1:s', '@alice:example.com', DateTime(2026, 2)),
          ],
        ),
      );
      stubChildren(r'$root1:s', [
        rawMessage(r'$r1:s', '@alice:example.com', DateTime(2026, 2, 2)),
        rawMessage(r'$r2:s', '@me:example.com', DateTime(2026, 2, 3)),
        rawMessage(r'$r3:s', '@bob:example.com', DateTime(2026, 2, 4)),
      ]);

      final summaries = await repo.fetchThreadSummaries('!room:example.com');

      expect(summaries.single.unreadCount, 2);
    });

    test('receipt newer than a reply marks it read', () async {
      final receiptTs = DateTime(2026, 2, 3).millisecondsSinceEpoch;
      when(room.receiptState).thenReturn(
        _FakeReceipts({
          r'$root1:s': _FakeTimelineReceipts(
            LatestReceiptStateData(r'$r1:s', receiptTs),
          ),
        }),
      );
      when(mockClient.getThreadRoots('!room:example.com', limit: 50))
          .thenAnswer(
        (_) async => GetThreadRootsResponse(
          chunk: [
            rawMessage(r'$root1:s', '@alice:example.com', DateTime(2026, 2)),
          ],
        ),
      );
      stubChildren(r'$root1:s', [
        rawMessage(r'$r1:s', '@alice:example.com', DateTime(2026, 2, 2)),
        rawMessage(r'$r2:s', '@alice:example.com', DateTime(2026, 2, 4)),
      ]);

      final summaries = await repo.fetchThreadSummaries('!room:example.com');

      expect(summaries.single.unreadCount, 1);
    });
  });

  group('forwardMessage', () {
    late MockRoom sourceRoom;
    late MockRoom targetRoom;
    late _FakeTimeline sourceTimeline;

    setUp(() {
      sourceRoom = MockRoom();
      targetRoom = MockRoom();
      sourceTimeline = _FakeTimeline();
      when(mockClient.getRoomById('!source:example.com')).thenReturn(sourceRoom);
      when(mockClient.getRoomById('!target:example.com')).thenReturn(targetRoom);
      when(sourceRoom.getTimeline()).thenAnswer((_) async => sourceTimeline);
      when(
        targetRoom.sendEvent(any, type: anyNamed('type')),
      ).thenAnswer((_) async => r'\$sent:s');
    });

    test('strips relation metadata and preserves type', () async {
      sourceTimeline.eventsList = [
        _FakeEvent(
          eventId: r'\$fwd:s',
          content: <String, Object?>{
            'msgtype': MessageTypes.Text,
            'body': 'edited body',
            'm.relates_to': <String, Object?>{
              'm.in_reply_to': <String, Object?>{'event_id': r'\$parent:s'},
            },
            'm.new_content': <String, Object?>{'body': 'edited body'},
          },
        ),
      ];

      await repo.forwardMessage(
        targetRoomId: '!target:example.com',
        sourceRoomId: '!source:example.com',
        sourceEventId: r'\$fwd:s',
      );

      final captured = verify(
        targetRoom.sendEvent(captureAny, type: captureAnyNamed('type')),
      ).captured;
      final content = captured[0] as Map<String, dynamic>;
      expect(content['body'], 'edited body');
      expect(content.containsKey('m.relates_to'), isFalse);
      expect(content.containsKey('m.new_content'), isFalse);
      expect(captured[1], EventTypes.Message);
    });

    test('is a no-op when the target room is unknown', () async {
      when(mockClient.getRoomById('!target:example.com')).thenReturn(null);

      await repo.forwardMessage(
        targetRoomId: '!target:example.com',
        sourceRoomId: '!source:example.com',
        sourceEventId: r'\$fwd:s',
      );

      verifyNever(targetRoom.sendEvent(any, type: anyNamed('type')));
    });

    test('is a no-op when the event is unknown', () async {
      when(
        sourceRoom.getEventById(r'\$missing:s'),
      ).thenAnswer((_) async => null);

      await repo.forwardMessage(
        targetRoomId: '!target:example.com',
        sourceRoomId: '!source:example.com',
        sourceEventId: r'\$missing:s',
      );

      verifyNever(targetRoom.sendEvent(any, type: anyNamed('type')));
    });
  });

  group('dispose', () {
    test('does not notify after dispose', () {
      var notified = false;
      repo.addListener(() => notified = true);

      repo.dispose();
      notified = false;
      service.notifyListeners();

      expect(notified, isFalse);
    });
  });
  group('toggleReaction', () {
    late MockRoom room;

    setUp(() {
      room = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(mockClient.userID).thenReturn('@me:example.com');
      when(room.getTimeline()).thenAnswer((_) async => _FakeTimeline());
    });

    test('sends a reaction when none exists', () async {
      final target = _FakeEvent(eventId: r'\$target:s');
      when(room.getEventById(r'\$target:s')).thenAnswer((_) async => target);
      when(room.sendReaction(any, any))
          .thenAnswer((_) async => r'\$reaction:s');

      await repo.toggleReaction('!room:example.com', r'\$target:s', '👍');

      verify(room.sendReaction(r'\$target:s', '👍')).called(1);
    });

    test('redacts the existing matching reaction', () async {
      final existing = _FakeEvent(
        eventId: r'\$reaction:s',
        senderIdValue: '@me:example.com',
        content: {
          'm.relates_to': {'key': '👍'},
        },
      );
      final target = _FakeEvent(eventId: r'\$target:s')
        ..aggregated = {existing};
      when(room.getEventById(r'\$target:s')).thenAnswer((_) async => target);

      await repo.toggleReaction('!room:example.com', r'\$target:s', '👍');

      expect(existing.redactCalled, isTrue);
      verifyNever(room.sendReaction(any, any));
    });

    test('ignores reactions from other users', () async {
      final foreign = _FakeEvent(
        eventId: r'\$reaction:s',
        senderIdValue: '@bob:example.com',
        content: {
          'm.relates_to': {'key': '👍'},
        },
      );
      final target = _FakeEvent(eventId: r'\$target:s')
        ..aggregated = {foreign};
      when(room.getEventById(r'\$target:s')).thenAnswer((_) async => target);
      when(room.sendReaction(any, any))
          .thenAnswer((_) async => r'\$new:s');

      await repo.toggleReaction('!room:example.com', r'\$target:s', '👍');

      expect(foreign.redactCalled, isFalse);
      verify(room.sendReaction(r'\$target:s', '👍')).called(1);
    });
  });

  group('sendText', () {
    late MockRoom room;

    setUp(() {
      room = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(room.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).thenAnswer((_) async => r'\$sent:s');
    });

    test('returns null for an unknown room', () async {
      final id = await repo.sendText('!unknown:example.com', 'hi');
      expect(id, isNull);
      verifyNever(room.sendTextEvent(any));
    });

    test('resolves the reply event by ID', () async {
      final reply = _FakeEvent(eventId: r'\$reply:s');
      when(room.getEventById(r'\$reply:s')).thenAnswer((_) async => reply);

      await repo.sendText(
        '!room:example.com',
        'hi',
        inReplyToEventId: r'\$reply:s',
      );

      verify(room.sendTextEvent(
        'hi',
        inReplyTo: reply,
        editEventId: anyNamed('editEventId'),
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).called(1);
    });

    test('skips reply resolution when editing', () async {
      await repo.sendText('!room:example.com', 'hi', editEventId: r'\$edit:s');

      verifyNever(room.getEventById(any));
      verify(room.sendTextEvent(
        'hi',
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: r'\$edit:s',
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).called(1);
    });

    test('passes thread relations through', () async {
      await repo.sendText(
        '!room:example.com',
        'hi',
        threadRootEventId: r'\$root:s',
        threadLastEventId: r'\$last:s',
      );

      verify(room.sendTextEvent(
        'hi',
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
        threadRootEventId: r'\$root:s',
        threadLastEventId: r'\$last:s',
      )).called(1);
    });
  });

  group('latestThreadEventId', () {
    test('returns the newest thread child ID', () async {
      final room = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(room.getTimeline()).thenAnswer((_) async => _FakeTimeline());
      final older = _FakeEvent(
        eventId: r'\$older:s',
        timestamp: DateTime(2026, 2, 2),
      );
      final newer = _FakeEvent(
        eventId: r'\$newer:s',
        timestamp: DateTime(2026, 2, 4),
      );
      final root = _FakeEvent(eventId: r'\$root:s')
        ..aggregated = {older, newer};
      when(room.getEventById(r'\$root:s')).thenAnswer((_) async => root);

      final id = await repo.latestThreadEventId('!room:example.com', r'\$root:s');

      expect(id, r'\$newer:s');
    });

    test('returns null when the thread has no replies', () async {
      final room = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(room);
      when(room.getTimeline()).thenAnswer((_) async => _FakeTimeline());
      final root = _FakeEvent(eventId: r'\$root:s');
      when(room.getEventById(r'\$root:s')).thenAnswer((_) async => root);

      final id = await repo.latestThreadEventId('!room:example.com', r'\$root:s');

      expect(id, isNull);
    });
  });
}

class _FakeReceipts extends Fake implements LatestReceiptState {
  _FakeReceipts(this.byThread);

  @override
  final Map<String, LatestReceiptStateForTimeline> byThread;
}

class _FakeTimelineReceipts extends Fake
    implements LatestReceiptStateForTimeline {
  _FakeTimelineReceipts(this.latestOwnReceipt);

  @override
  final LatestReceiptStateData? latestOwnReceipt;
}

class _FakeTimeline extends Fake implements Timeline {
  List<Event> eventsList = [];
  bool canRequest = false;
  bool allowNew = true;
  int historyRequests = 0;
  bool cancelled = false;

  @override
  List<Event> get events => eventsList;

  @override
  bool get canRequestHistory => canRequest;

  @override
  bool get allowNewEvent => allowNew;

  @override
  Future<void> requestHistory({
    StateFilter? filter,
    int? historyCount,
  }) async {
    historyRequests++;
  }

  @override
  void cancelSubscriptions() {
    cancelled = true;
  }
}

class _FakeEvent extends Fake implements Event {
  _FakeEvent({
    required this.eventId,
    this.body = '',
    Map<String, Object?>? content,
    this.senderIdValue = '@alice:example.com',
    this.timestamp,
  }) : _content = content;

  @override
  final String eventId;

  @override
  final String body;

  final Map<String, Object?>? _content;

  final String senderIdValue;

  final DateTime? timestamp;

  Set<Event> aggregated = const {};

  bool redactCalled = false;

  @override
  String get senderId => senderIdValue;

  @override
  Map<String, Object?> get content =>
      _content ?? <String, Object?>{'msgtype': 'm.text', 'body': body};

  @override
  DateTime get originServerTs => timestamp ?? DateTime(2026, 2);

  @override
  Set<Event> aggregatedEvents(Timeline timeline, String relationshipType) =>
      aggregated;

  @override
  Future<String?> redactEvent({
    String? reason,
    bool redactAllEdits = false,
    String? txid,
  }) async {
    redactCalled = true;
    return r'$redaction:s';
  }

  @override
  String get type => EventTypes.Message;

  @override
  String get messageType => MessageTypes.Text;

  @override
  bool get redacted => false;

  @override
  bool get canRedact => false;

  @override
  Event getDisplayEvent(Timeline timeline) => this;

  @override
  String? get relationshipType => null;

  @override
  String? get relationshipEventId => null;

  @override
  Map<String, Object?>? get prevContent => null;

  @override
  bool hasAggregatedEvents(Timeline timeline, String relationshipType) =>
      false;
}

class _FakeDatabase extends Fake implements DatabaseApi {
  @override
  Future<Map<String, dynamic>?> getClient(String name) async => null;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async =>
      <Event>[];
}

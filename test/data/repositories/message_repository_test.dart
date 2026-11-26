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
  _FakeEvent({required this.eventId, this.body = ''});

  @override
  final String eventId;

  @override
  final String body;

  @override
  String get senderId => '@alice:example.com';

  @override
  String get type => EventTypes.Message;

  @override
  String get messageType => MessageTypes.Text;

  @override
  DateTime get originServerTs => DateTime(2026, 2);

  @override
  bool get redacted => false;

  @override
  bool get canRedact => false;

  @override
  Map<String, Object?> get content => <String, Object?>{'body': body};

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

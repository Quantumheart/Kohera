import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Timeline>(),
  MockSpec<Room>(),
])
import 'thread_summary_test.mocks.dart';

const _me = '@me:example.com';
const _other = '@other:example.com';

MockEvent _event({
  required String id,
  required String sender,
  required int ts,
  String? threadRootId,
}) {
  final e = MockEvent();
  when(e.eventId).thenReturn(id);
  when(e.senderId).thenReturn(sender);
  when(e.originServerTs).thenReturn(DateTime.fromMillisecondsSinceEpoch(ts));
  when(e.relationshipType)
      .thenReturn(threadRootId == null ? null : RelationshipTypes.thread);
  when(e.relationshipEventId).thenReturn(threadRootId);
  return e;
}

void _wireThreadAggregation({
  required MockEvent root,
  required MockTimeline timeline,
  required Set<Event> children,
}) {
  when(root.hasAggregatedEvents(timeline, RelationshipTypes.thread))
      .thenReturn(children.isNotEmpty);
  when(root.aggregatedEvents(timeline, RelationshipTypes.thread))
      .thenReturn(children);
}

MockRoom _roomWithReceipt({String? rootId, int? ts}) {
  final room = MockRoom();
  final state = LatestReceiptState.empty();
  if (rootId != null && ts != null) {
    state.byThread[rootId] = LatestReceiptStateForTimeline.empty()
      ..latestOwnReceipt = LatestReceiptStateData('e', ts);
  }
  when(room.receiptState).thenReturn(state);
  return room;
}

void main() {
  group('deriveThreadSummaries', () {
    late MockTimeline timeline;

    setUp(() {
      timeline = MockTimeline();
    });

    test('returns roots with thread aggregations sorted by latest reply', () {
      final rootA = _event(id: r'$rootA', sender: _other, ts: 1000);
      final rootB = _event(id: r'$rootB', sender: _other, ts: 1100);
      final replyA = _event(
          id: r'$replyA', sender: _other, ts: 2000, threadRootId: r'$rootA',);
      final replyB = _event(
          id: r'$replyB', sender: _other, ts: 3000, threadRootId: r'$rootB',);

      _wireThreadAggregation(
          root: rootA, timeline: timeline, children: {replyA},);
      _wireThreadAggregation(
          root: rootB, timeline: timeline, children: {replyB},);
      when(timeline.events).thenReturn([rootA, rootB, replyA, replyB]);

      final summaries = deriveThreadSummaries(
        timeline: timeline,
        room: _roomWithReceipt(),
        myUserId: _me,
      );

      expect(summaries.map((s) => s.root.eventId), [r'$rootB', r'$rootA']);
    });

    test('skips events that are themselves thread replies', () {
      final root = _event(id: r'$root', sender: _other, ts: 1000);
      final reply =
          _event(id: r'$r', sender: _other, ts: 2000, threadRootId: r'$root');
      _wireThreadAggregation(
          root: root, timeline: timeline, children: {reply},);
      when(timeline.events).thenReturn([root, reply]);

      final summaries = deriveThreadSummaries(
        timeline: timeline,
        room: _roomWithReceipt(),
        myUserId: _me,
      );

      expect(summaries, hasLength(1));
      expect(summaries.single.root.eventId, r'$root');
    });

    test('skips roots with no thread aggregation', () {
      final root = _event(id: r'$root', sender: _other, ts: 1000);
      when(root.hasAggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn(false);
      when(timeline.events).thenReturn([root]);

      final summaries = deriveThreadSummaries(
        timeline: timeline,
        room: _roomWithReceipt(),
        myUserId: _me,
      );

      expect(summaries, isEmpty);
    });

    test('unreadCount counts other-user replies newer than thread receipt', () {
      final root = _event(id: r'$root', sender: _other, ts: 1000);
      final r1 = _event(
          id: r'$r1', sender: _other, ts: 2000, threadRootId: r'$root');
      final r2 = _event(
          id: r'$r2', sender: _me, ts: 3000, threadRootId: r'$root');
      final r3 = _event(
          id: r'$r3', sender: _other, ts: 4000, threadRootId: r'$root');
      _wireThreadAggregation(
          root: root, timeline: timeline, children: {r1, r2, r3},);
      when(timeline.events).thenReturn([root, r1, r2, r3]);

      final summaries = deriveThreadSummaries(
        timeline: timeline,
        room: _roomWithReceipt(rootId: r'$root', ts: 2500),
        myUserId: _me,
      );

      expect(summaries.single.unreadCount, 1);
    });

    test('unreadCount = all other-user replies when receipt absent', () {
      final root = _event(id: r'$root', sender: _other, ts: 1000);
      final r1 = _event(
          id: r'$r1', sender: _other, ts: 2000, threadRootId: r'$root');
      final r2 = _event(
          id: r'$r2', sender: _other, ts: 3000, threadRootId: r'$root');
      _wireThreadAggregation(
          root: root, timeline: timeline, children: {r1, r2},);
      when(timeline.events).thenReturn([root, r1, r2]);

      final summaries = deriveThreadSummaries(
        timeline: timeline,
        room: _roomWithReceipt(),
        myUserId: _me,
      );

      expect(summaries.single.unreadCount, 2);
    });

    test('unreadCount ignores own replies regardless of timestamp', () {
      final root = _event(id: r'$root', sender: _me, ts: 1000);
      final r1 = _event(
          id: r'$r1', sender: _me, ts: 5000, threadRootId: r'$root');
      _wireThreadAggregation(
          root: root, timeline: timeline, children: {r1},);
      when(timeline.events).thenReturn([root, r1]);

      final summaries = deriveThreadSummaries(
        timeline: timeline,
        room: _roomWithReceipt(),
        myUserId: _me,
      );

      expect(summaries.single.unreadCount, 0);
    });
  });

  group('totalThreadUnread', () {
    test('sums unread across summaries', () {
      final summaries = [
        ThreadSummary(
            root: MockEvent(), children: const [], unreadCount: 2,),
        ThreadSummary(
            root: MockEvent(), children: const [], unreadCount: 0,),
        ThreadSummary(
            root: MockEvent(), children: const [], unreadCount: 3,),
      ];
      expect(totalThreadUnread(summaries), 5);
    });
  });
}

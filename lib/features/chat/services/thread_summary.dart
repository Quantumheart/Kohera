import 'package:matrix/matrix.dart';

class ThreadSummary {
  ThreadSummary({
    required this.root,
    required this.children,
    required this.unreadCount,
  });

  final Event root;
  final List<Event> children;
  final int unreadCount;

  Event? get lastReply => children.isEmpty ? null : children.last;

  DateTime get lastActivity =>
      lastReply?.originServerTs ?? root.originServerTs;

  int get replyCount => children.length;
}

List<ThreadSummary> deriveThreadSummaries({
  required Timeline timeline,
  required Room room,
  required String myUserId,
}) {
  final summaries = <ThreadSummary>[];
  for (final event in timeline.events) {
    if (event.relationshipType == RelationshipTypes.thread) continue;
    if (!event.hasAggregatedEvents(timeline, RelationshipTypes.thread)) {
      continue;
    }
    final children = event
        .aggregatedEvents(timeline, RelationshipTypes.thread)
        .toList()
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    summaries.add(
      ThreadSummary(
        root: event,
        children: children,
        unreadCount: unreadCountFromChildren(
          rootEventId: event.eventId,
          children: children,
          room: room,
          myUserId: myUserId,
        ),
      ),
    );
  }
  summaries.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return summaries;
}

int unreadCountFromChildren({
  required String rootEventId,
  required List<Event> children,
  required Room room,
  required String myUserId,
}) {
  final receipt = room.receiptState.byThread[rootEventId]?.latestOwnReceipt;
  final receiptTs = receipt?.ts ?? 0;
  var count = 0;
  for (final child in children) {
    if (child.senderId == myUserId) continue;
    if (child.originServerTs.millisecondsSinceEpoch > receiptTs) count++;
  }
  return count;
}

int totalThreadUnread(List<ThreadSummary> summaries) =>
    summaries.fold(0, (sum, s) => sum + s.unreadCount);

int threadUnreadCountFor({
  required Event root,
  required Timeline timeline,
  required Room room,
  required String myUserId,
}) {
  if (!root.hasAggregatedEvents(timeline, RelationshipTypes.thread)) {
    return 0;
  }
  final children =
      root.aggregatedEvents(timeline, RelationshipTypes.thread).toList();
  return unreadCountFromChildren(
    rootEventId: root.eventId,
    children: children,
    room: room,
    myUserId: myUserId,
  );
}

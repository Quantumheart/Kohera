import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:matrix/matrix.dart';

Future<List<ThreadSummary>> fetchThreadSummaries({
  required Client client,
  required Room room,
  int limit = 50,
}) async {
  final myUserId = client.userID ?? '';
  final response = await client.getThreadRoots(room.id, limit: limit);

  final summaries = <ThreadSummary>[];
  for (final raw in response.chunk) {
    final root = Event.fromMatrixEvent(raw, room);
    final children = await _fetchChildren(client, room, root.eventId);
    summaries.add(
      ThreadSummary(
        root: root,
        children: children,
        unreadCount: unreadCountFromChildren(
          rootEventId: root.eventId,
          children: children,
          room: room,
          myUserId: myUserId,
        ),
      ),
    );
  }
  return summaries;
}

Future<List<Event>> _fetchChildren(
  Client client,
  Room room,
  String rootEventId,
) async {
  final relations = await client.getRelatingEventsWithRelType(
    room.id,
    rootEventId,
    RelationshipTypes.thread,
    limit: 100,
  );
  return relations.chunk
      .map((m) => Event.fromMatrixEvent(m, room))
      .toList()
    ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
}

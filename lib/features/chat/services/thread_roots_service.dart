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
    final root = await _decryptIfNeeded(
      client,
      Event.fromMatrixEvent(raw, room),
    );
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
  final events = <Event>[];
  for (final raw in relations.chunk) {
    events.add(
      await _decryptIfNeeded(client, Event.fromMatrixEvent(raw, room)),
    );
  }
  events.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
  return events;
}

Future<Event> _decryptIfNeeded(Client client, Event event) async {
  if (event.type != EventTypes.Encrypted) return event;
  final encryption = client.encryption;
  if (encryption == null) return event;
  try {
    final decrypted = await encryption
        .decryptRoomEvent(event)
        .timeout(const Duration(seconds: 3));
    return decrypted;
  } catch (_) {
    return event;
  }
}

import 'package:matrix/matrix.dart';

class ThreadChildrenPage {
  ThreadChildrenPage({required this.events, this.nextBatch});

  final List<Event> events;
  final String? nextBatch;
}

Future<ThreadChildrenPage> fetchThreadChildrenPage(
  Client client,
  Room room,
  String rootEventId, {
  String? from,
  int limit = 100,
}) async {
  final relations = await client.getRelatingEventsWithRelType(
    room.id,
    rootEventId,
    RelationshipTypes.thread,
    limit: limit,
    from: from,
  );
  final events = <Event>[];
  for (final raw in relations.chunk) {
    events.add(
      await _decryptIfNeeded(client, Event.fromMatrixEvent(raw, room)),
    );
  }
  events.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
  return ThreadChildrenPage(events: events, nextBatch: relations.nextBatch);
}

Future<List<Event>> fetchThreadChildren(
  Client client,
  Room room,
  String rootEventId,
) async {
  final page = await fetchThreadChildrenPage(client, room, rootEventId);
  return page.events;
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

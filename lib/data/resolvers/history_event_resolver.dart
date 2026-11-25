import 'package:kohera/data/models/kohera_room_history.dart';
import 'package:matrix/matrix.dart';

/// Converts an SDK `Event` into a [KoheraHistoryEvent] for history export.
class HistoryEventResolver {
  const HistoryEventResolver();

  KoheraHistoryEvent convert(Room room, Event event) {
    final sender = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
    String? mediaUrl;
    String? mediaFileName;
    String? mediaMimetype;
    if (event.hasAttachment) {
      mediaUrl = event.attachmentMxcUrl?.toString();
      mediaFileName = event.text.isNotEmpty ? event.text : null;
      mediaMimetype = event.attachmentMimetype.isNotEmpty
          ? event.attachmentMimetype
          : null;
    }
    return KoheraHistoryEvent(
      eventId: event.eventId,
      senderId: event.senderId,
      senderDisplayname: sender.calcDisplayname(),
      timestamp: event.originServerTs,
      messageType: event.messageType,
      body: event.body,
      formattedBody:
          event.formattedText.isNotEmpty ? event.formattedText : null,
      hasAttachment: event.hasAttachment,
      mediaUrl: mediaUrl,
      mediaFileName: mediaFileName,
      mediaMimetype: mediaMimetype,
    );
  }
}

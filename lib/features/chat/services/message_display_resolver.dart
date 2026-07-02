import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:matrix/matrix.dart';

/// Converts an SDK [Event] (+ optional [Timeline]) into a pre-computed
/// [KoheraMessageDisplay] for the chat message rendering widget tree.
///
/// This is the conversion boundary — the only place in the message rendering
/// path that touches the Matrix SDK. Display widgets below consume
/// [KoheraMessageDisplay] and never import `package:matrix/matrix.dart`.
class MessageDisplayResolver {
  const MessageDisplayResolver();

  KoheraMessageDisplay call(Event event, {Timeline? timeline}) {
    final displayEvent =
        timeline != null ? event.getDisplayEvent(timeline) : event;
    final sender = event.senderFromMemoryOrFallback;
    final senderName = sender.calcDisplayname();
    final senderAvatarUrl = sender.avatarUrl?.toString();

    final isRedacted = event.redacted;
    String? redactorId;
    String? redactorName;
    String? redactionReason;
    if (isRedacted) {
      final redactedBecause = event.redactedBecause;
      redactorId = redactedBecause?.senderId;
      if (redactorId != null && redactorId != event.senderId) {
        redactorName = event.room.unsafeGetUserFromMemoryOrFallback(
          redactorId,
        ).displayName;
      }
      redactionReason = redactedBecause?.content.tryGet<String>('reason');
    }

    final replyEventId = extractReplyEventId(event.content);
    final bodyText = replyEventId != null
        ? stripReplyFallback(displayEvent.body)
        : displayEvent.body;

    final formattedText = displayEvent.formattedText;
    final formattedHtml = (formattedText.isNotEmpty &&
            displayEvent.content['format'] == 'org.matrix.custom.html')
        ? formattedText
        : null;

    final status = event.status.isError
        ? KoheraMessageStatus.error
        : (event.status.isSent || event.status.isSynced
            ? KoheraMessageStatus.sent
            : KoheraMessageStatus.sending);

    String? threadRootId;
    var isEdited = false;
    if (timeline != null) {
      if (event.hasAggregatedEvents(timeline, RelationshipTypes.thread)) {
        threadRootId = event.eventId;
      }
      isEdited = !isRedacted &&
          event.hasAggregatedEvents(timeline, RelationshipTypes.edit);
    }

    return KoheraMessageDisplay(
      eventId: event.eventId,
      senderId: event.senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      body: bodyText,
      formattedHtml: formattedHtml,
      messageType: displayEvent.messageType,
      eventType: event.type,
      timestamp: event.originServerTs,
      isRedacted: isRedacted,
      redactorId: redactorId,
      redactorName: redactorName,
      redactionReason: redactionReason,
      status: status,
      transactionId: event.transactionId,
      threadRootId: threadRootId,
      isEdited: isEdited,
      replyEventId: replyEventId,
      content: event.content,
    );
  }
}

/// Extracts the reply-to event ID from a Matrix event content map.
///
/// Uses the SDK's `tryGet` extension. Kept here (in the matrix-importing file)
/// so display widgets don't need the SDK.
String? extractReplyEventId(Map<String, Object?> content) {
  return content
      .tryGet<Map<String, Object?>>('m.relates_to')
      ?.tryGet<Map<String, Object?>>('m.in_reply_to')
      ?.tryGet<String>('event_id');
}

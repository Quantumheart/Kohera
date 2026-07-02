import 'package:flutter/foundation.dart';

import 'package:kohera/features/chat/models/kohera_message_status.dart';

/// A Kohera-owned domain model representing a Matrix message event with
/// pre-computed display fields.
///
/// This is the display model for the chat message rendering widget tree. It
/// carries no `package:matrix/matrix.dart` dependency — the SDK `Event` is
/// converted to this type at the conversion boundary (`ChatMessageItem`,
/// which retains `Event` + `Timeline` access) via `MessageDisplayResolver`.
///
/// Display widgets below the boundary (`MessageBubble`, `MessageBubbleBody`,
/// `MessageBubbleContent`, etc.) consume this model and never touch the
/// Matrix SDK directly.
@immutable
class KoheraMessageDisplay {
  const KoheraMessageDisplay({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.messageType,
    required this.eventType,
    required this.timestamp,
    required this.status,
    required this.content,
    this.isEdited = false,
    this.isRedacted = false,
    this.senderAvatarUrl,
    this.formattedHtml,
    this.redactorId,
    this.redactorName,
    this.redactionReason,
    this.transactionId,
    this.threadRootId,
    this.replyEventId,
  });

  /// The Matrix event ID (e.g. `$1234:example.com`).
  final String eventId;

  /// The Matrix user ID of the sender (e.g. `@alice:example.com`).
  final String senderId;

  /// The resolved sender display name. Produced by
  /// `User.calcDisplayname()` at the conversion boundary.
  final String senderName;

  /// The raw `mxc://` avatar URI as a string, or `null`.
  final String? senderAvatarUrl;

  /// The message body text (reply fallback stripped).
  final String body;

  /// Pre-computed formatted HTML body, or `null` if the message is not
  /// HTML-formatted.
  final String? formattedHtml;

  /// The Matrix `msgtype` (e.g. `m.text`, `m.emote`, `m.image`).
  final String messageType;

  /// The Matrix event type (e.g. `m.room.message`, `m.call.invite`).
  final String eventType;

  /// The server timestamp of the event.
  final DateTime timestamp;

  /// Whether this message has been redacted.
  final bool isRedacted;

  /// The user ID of the redactor, if redacted.
  final String? redactorId;

  /// The display name of the redactor, if redacted and not the sender.
  final String? redactorName;

  /// The reason given for redaction, if any.
  final String? redactionReason;

  /// The send status of this message.
  final KoheraMessageStatus status;

  /// The local transaction ID for outgoing messages, if any.
  final String? transactionId;

  /// The thread root event ID if this message is a thread root, `null`
  /// otherwise.
  final String? threadRootId;

  /// Whether this message has been edited.
  final bool isEdited;

  /// The event ID of the replied-to message, if this is a reply.
  final String? replyEventId;

  /// The raw event content map. Carried for event-type-specific fields
  /// (e.g. call events read `content['reason']`, `content['call_id']`).
  final Map<String, Object?> content;

  KoheraMessageDisplay copyWith({
    String? eventId,
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
    String? body,
    String? formattedHtml,
    String? messageType,
    String? eventType,
    DateTime? timestamp,
    bool? isRedacted,
    String? redactorId,
    String? redactorName,
    String? redactionReason,
    KoheraMessageStatus? status,
    String? transactionId,
    String? threadRootId,
    bool? isEdited,
    String? replyEventId,
    Map<String, Object?>? content,
  }) =>
      KoheraMessageDisplay(
        eventId: eventId ?? this.eventId,
        senderId: senderId ?? this.senderId,
        senderName: senderName ?? this.senderName,
        senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
        body: body ?? this.body,
        formattedHtml: formattedHtml ?? this.formattedHtml,
        messageType: messageType ?? this.messageType,
        eventType: eventType ?? this.eventType,
        timestamp: timestamp ?? this.timestamp,
        isRedacted: isRedacted ?? this.isRedacted,
        redactorId: redactorId ?? this.redactorId,
        redactorName: redactorName ?? this.redactorName,
        redactionReason: redactionReason ?? this.redactionReason,
        status: status ?? this.status,
        transactionId: transactionId ?? this.transactionId,
        threadRootId: threadRootId ?? this.threadRootId,
        isEdited: isEdited ?? this.isEdited,
        replyEventId: replyEventId ?? this.replyEventId,
        content: content ?? this.content,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraMessageDisplay && eventId == other.eventId;

  @override
  int get hashCode => eventId.hashCode;

  @override
  String toString() =>
      'KoheraMessageDisplay(eventId: $eventId, senderId: $senderId, '
      'senderName: $senderName, messageType: $messageType, '
      'eventType: $eventType, isRedacted: $isRedacted, status: $status)';
}

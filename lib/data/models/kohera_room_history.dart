import 'package:flutter/foundation.dart';

/// A single `m.room.message` event from a full-history pagination,
/// resolved for export. SDK-free.
@immutable
class KoheraHistoryEvent {
  const KoheraHistoryEvent({
    required this.eventId,
    required this.senderId,
    required this.senderDisplayname,
    required this.timestamp,
    required this.messageType,
    required this.body,
    this.formattedBody,
    this.hasAttachment = false,
    this.mediaUrl,
    this.mediaFileName,
    this.mediaMimetype,
  });

  final String eventId;
  final String senderId;
  final String senderDisplayname;
  final DateTime timestamp;
  final String messageType;
  final String body;
  final String? formattedBody;
  final bool hasAttachment;
  final String? mediaUrl;
  final String? mediaFileName;
  final String? mediaMimetype;
}

/// Full message history of a room plus its display metadata. SDK-free.
@immutable
class KoheraRoomHistory {
  const KoheraRoomHistory({
    required this.roomId,
    required this.displayname,
    required this.events,
    this.canonicalAlias,
    this.topic,
  });

  final String roomId;
  final String displayname;
  final String? canonicalAlias;
  final String? topic;

  /// `m.room.message` events in newest-first pagination order.
  final List<KoheraHistoryEvent> events;
}

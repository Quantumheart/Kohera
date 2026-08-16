// coverage:ignore-file

import 'package:kohera/core/backend/dto/dto.dart';
import 'package:matrix/matrix.dart';

class EventDto implements Dto {
  final String eventId;
  final String roomId;
  final String senderId;
  final String senderDisplayName;
  final String? senderAvatarMxc;
  final String type;
  final String? messageType;
  final String? body;
  final Map<String, dynamic> content;
  final Map<String, dynamic>? prevContent;
  final int originServerTs;
  final bool redacted;
  final String status;
  final String? relationshipType;
  final String? relationshipEventId;
  final String? transactionId;
  final String? stateKey;

  // Computed fields (require Timeline/Room context on the worker)
  final EventDto? displayEvent;
  final bool hasAggregatedEvents;
  final bool canRedact;
  final int reactionCount;
  final int threadReplyCount;

  const EventDto({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.senderDisplayName,
    required this.type,
    required this.content,
    required this.originServerTs,
    required this.redacted,
    required this.status,
    required this.hasAggregatedEvents,
    required this.canRedact,
    required this.reactionCount,
    required this.threadReplyCount,
    this.senderAvatarMxc,
    this.messageType,
    this.body,
    this.prevContent,
    this.relationshipType,
    this.relationshipEventId,
    this.transactionId,
    this.stateKey,
    this.displayEvent,
  });

  factory EventDto.fromSdk(
      Event event, {
        Timeline? timeline,
        Room? room,
        int depth = 0,
      }) {
    final sender = event.senderFromMemoryOrFallback;
    return EventDto(
      eventId: event.eventId,
      roomId: event.roomId ?? '',
      senderId: event.senderId,
      senderDisplayName: sender.displayName ?? event.senderId,
      senderAvatarMxc: sender.avatarUrl?.toString(),
      type: event.type,
      messageType: event.messageType,
      body: event.body,
      content: event.content,
      prevContent: event.prevContent,
      originServerTs: event.originServerTs.millisecondsSinceEpoch,
      redacted: event.redacted,
      status: event.status.name,
      relationshipType: event.relationshipType,
      relationshipEventId: event.relationshipEventId,
      transactionId: event.transactionId,
      stateKey: event.stateKey,
      displayEvent: timeline != null && depth < 1
          ? EventDto.fromSdk(
        event.getDisplayEvent(timeline),
        timeline: timeline,
        room: room,
        depth: depth + 1,
      )
          : null,
      hasAggregatedEvents: timeline != null &&
          (event.aggregatedEvents(timeline, RelationshipTypes.reaction).isNotEmpty ||
              event.aggregatedEvents(timeline, RelationshipTypes.thread).isNotEmpty),
      canRedact: room != null && event.canRedact,
      reactionCount: timeline != null
          ? event.aggregatedEvents(timeline, RelationshipTypes.reaction).length
          : 0,
      threadReplyCount: timeline != null
          ? event.aggregatedEvents(timeline, RelationshipTypes.thread).length
          : 0,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'eventId': eventId,
    'roomId': roomId,
    'senderId': senderId,
    'senderDisplayName': senderDisplayName,
    'senderAvatarMxc': senderAvatarMxc,
    'type': type,
    'messageType': messageType,
    'body': body,
    'content': content,
    'prevContent': prevContent,
    'originServerTs': originServerTs,
    'redacted': redacted,
    'status': status,
    'relationshipType': relationshipType,
    'relationshipEventId': relationshipEventId,
    'transactionId': transactionId,
    'stateKey': stateKey,
    'displayEvent': displayEvent?.toMap(),
    'hasAggregatedEvents': hasAggregatedEvents,
    'canRedact': canRedact,
    'reactionCount': reactionCount,
    'threadReplyCount': threadReplyCount,
  };

  factory EventDto.fromMap(Map<String, dynamic> m) => EventDto(
    eventId: m['eventId'] as String,
    roomId: m['roomId'] as String,
    senderId: m['senderId'] as String,
    senderDisplayName: m['senderDisplayName'] as String,
    senderAvatarMxc: m['senderAvatarMxc'] as String?,
    type: m['type'] as String,
    messageType: m['messageType'] as String?,
    body: m['body'] as String?,
    content: m['content'] as Map<String, dynamic>,
    prevContent: m['prevContent'] as Map<String, dynamic>?,
    originServerTs: m['originServerTs'] as int,
    redacted: m['redacted'] as bool,
    status: m['status'] as String,
    relationshipType: m['relationshipType'] as String?,
    relationshipEventId: m['relationshipEventId'] as String?,
    transactionId: m['transactionId'] as String?,
    stateKey: m['stateKey'] as String?,
    displayEvent: m['displayEvent'] != null
        ? EventDto.fromMap(m['displayEvent'] as Map<String, dynamic>)
        : null,
    hasAggregatedEvents: m['hasAggregatedEvents'] as bool,
    canRedact: m['canRedact'] as bool,
    reactionCount: m['reactionCount'] as int,
    threadReplyCount: m['threadReplyCount'] as int,
  );
}
import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/models/kohera_state_event_text.dart';
import 'package:kohera/features/chat/services/media_controller.dart';

/// The rendering category of a visible message in the timeline.
enum MessageCategory { message, callEvent, stateEvent, sticker }

/// Pre-computed data bundle for one visible message in the chat timeline.
///
/// Produced by [MessageTimelineController] at the SDK boundary. Display
/// widgets ([MessageListView], [ChatMessageItem]) consume this type and never
/// touch `package:matrix/matrix.dart` directly.
@immutable
class ChatMessageData {
  const ChatMessageData({
    required this.message,
    required this.category,
    required this.isMe,
    required this.isFirst,
    required this.isPinned,
    required this.canPin,
    required this.canRedact,
    required this.hasThread,
    required this.threadReplyCount,
    required this.threadUnreadCount,
    this.stateEventText,
    this.reactions,
    this.media,
    this.mediaController,
    this.callDuration,
  });

  /// The pre-computed message display model (always present).
  final KoheraMessageDisplay message;

  /// Which tile widget should render this message.
  final MessageCategory category;

  /// Pre-computed state event text (only for [MessageCategory.stateEvent]).
  final KoheraStateEventText? stateEventText;

  /// Pre-computed reaction list (for messages and stickers with reactions).
  final KoheraReactionList? reactions;

  /// Pre-computed media content (for stickers and media messages).
  final KoheraMediaContent? media;

  /// Media controller for media playback/download (for stickers and media).
  final MediaController? mediaController;

  /// Whether the sender is the current user.
  final bool isMe;

  /// Whether this is the first message from this sender in a group.
  final bool isFirst;

  /// Whether this message is pinned in the room.
  final bool isPinned;

  /// Whether the current user can pin/unpin this message.
  final bool canPin;

  /// Whether the current user can redact (delete) this message.
  final bool canRedact;

  /// Whether this message has thread replies.
  final bool hasThread;

  /// Number of thread replies.
  final int threadReplyCount;

  /// Number of unread thread replies.
  final int threadUnreadCount;

  /// Call duration (only for [MessageCategory.callEvent] hangup events).
  final Duration? callDuration;

  /// The event ID — convenience accessor.
  String get eventId => message.eventId;
}

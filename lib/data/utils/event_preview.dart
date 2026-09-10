import 'package:kohera/core/utils/poll_body.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/data/models/call_constants.dart';
import 'package:matrix/matrix.dart';

/// Canonical short strings for one-line event previews (room list, inbox).
abstract class EventPreviewText {
  static const noMessages = 'No messages yet';
  static const callInProgress = '📞 Call in progress';
  static const callStartedByYou = '📞 You started a call';
  static const incomingCall = '📞 Incoming call';
  static const missedCall = '📞 Missed call';
  static const callEnded = '📞 Call ended';
  static const youDeleted = 'You deleted this message';
  static const messageDeleted = 'This message was deleted';
  static String deletedBy(String who) => 'Deleted by $who';
  static const unableToDecrypt = '🔒 Unable to decrypt';
  static const image = '📷 Image';
  static const video = '🎬 Video';
  static const file = '📎 File';
  static const audio = '🎵 Audio';
}

/// Whether [event] is a call-related event (invite, hangup, or membership).
bool isCallEvent(Event event) =>
    event.type == kCallInvite ||
    event.type == kCallHangup ||
    event.type == kCallMember ||
    event.type == kCallMemberMsc ||
    event.body.contains(kCallMember) ||
    event.body.contains(kCallMemberMsc);

/// Builds a readable one-line preview for [event] shared by the room list and
/// the inbox. Handles calls, polls, redactions, undecryptable events, media
/// message types, and plain text. Falls back to the raw body otherwise.
String eventPreviewText(Event event, {required Room room, String? myUserId}) {
  final poll = pollStartBody(event);
  if (poll != null) return poll;

  if (event.type == kCallInvite) return EventPreviewText.callInProgress;
  if (event.type == kCallMember ||
      event.type == kCallMemberMsc ||
      event.body.contains(kCallMember) ||
      event.body.contains(kCallMemberMsc)) {
    return event.senderId == myUserId
        ? EventPreviewText.callStartedByYou
        : EventPreviewText.incomingCall;
  }
  if (event.type == kCallHangup) {
    final reason = event.content.tryGet<String>('reason');
    if (reason == kHangupInviteTimeout) return EventPreviewText.missedCall;
    return EventPreviewText.callEnded;
  }

  if (event.redacted) {
    final isMe = event.senderId == myUserId;
    if (isMe) return EventPreviewText.youDeleted;
    final redactor = event.redactedBecause?.senderId;
    final isSelfRedact = redactor == event.senderId;
    if (isSelfRedact || redactor == null) return EventPreviewText.messageDeleted;
    final redactorUser = room.unsafeGetUserFromMemoryOrFallback(redactor);
    return EventPreviewText.deletedBy(redactorUser.displayName ?? redactor);
  }

  if (event.messageType == MessageTypes.BadEncrypted) {
    return EventPreviewText.unableToDecrypt;
  }

  final body = stripReplyFallback(event.body);
  if (event.messageType == MessageTypes.Text) return body;
  if (event.messageType == MessageTypes.Image) return EventPreviewText.image;
  if (event.messageType == MessageTypes.Video) return EventPreviewText.video;
  if (event.messageType == MessageTypes.File) return EventPreviewText.file;
  if (event.messageType == MessageTypes.Audio) return EventPreviewText.audio;
  return body;
}

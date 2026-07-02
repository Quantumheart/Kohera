import 'package:flutter/foundation.dart';

import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:matrix/matrix.dart';

/// Converts an SDK [Event] into a pre-computed [KoheraReplyPreview] for the
/// reply/edit preview banner widget tree.
///
/// This is the conversion boundary for reply/edit preview rendering. Display
/// widgets below the boundary consume [KoheraReplyPreview] and never import
/// `package:matrix/matrix.dart`.
///
/// Use [resolveParent] for inline reply previews (where the parent event must
/// be resolved asynchronously via `getReplyEvent`). Use [fromEvent] for compose
/// reply/edit banners (where the event is already known and field extraction
/// is synchronous).
class ReplyPreviewResolver {
  const ReplyPreviewResolver();

  /// Resolves the parent (replied-to) event for inline reply previews.
  ///
  /// Calls `event.getReplyEvent(timeline)` and returns a [KoheraReplyPreview]
  /// with pre-computed display fields, or `null` if the parent is unavailable,
  /// redacted, or a redaction event.
  Future<KoheraReplyPreview?> resolveParent(
    Event replyEvent,
    Timeline timeline,
  ) async {
    Event? parent;
    try {
      parent = await replyEvent.getReplyEvent(timeline);
    } catch (e) {
      debugPrint('[Kohera] Failed to load reply parent: $e');
      return null;
    }
    if (parent == null ||
        parent.type == EventTypes.Redaction ||
        parent.redacted) {
      return null;
    }
    return _fromEvent(parent);
  }

  /// Builds a preview directly from an event (for compose reply/edit banners).
  ///
  /// Use this when the event is already known (e.g. the reply/edit target in
  /// the compose bar) and no async parent resolution is needed.
  KoheraReplyPreview fromEvent(Event event) => _fromEvent(event);

  KoheraReplyPreview _fromEvent(Event event) {
    final sender = event.senderFromMemoryOrFallback;
    final senderName = sender.displayName ?? event.senderId;
    final isBadEncrypted = event.messageType == MessageTypes.BadEncrypted;
    final body = isBadEncrypted
        ? 'Unable to decrypt'
        : stripReplyFallback(event.body);

    final formattedText = event.formattedText;
    final formattedHtml = (formattedText.isNotEmpty &&
            event.content['format'] == 'org.matrix.custom.html')
        ? formattedText
        : null;

    return KoheraReplyPreview(
      parentMessageId: event.eventId,
      parentSenderId: event.senderId,
      parentSenderName: senderName,
      parentBody: body,
      parentFormattedHtml: formattedHtml,
    );
  }
}

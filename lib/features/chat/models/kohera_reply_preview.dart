import 'package:flutter/foundation.dart';

/// A Kohera-owned domain model representing a preview of a parent or
/// referenced message for reply and edit preview banners.
///
/// This is the display model for the reply/edit preview widget tree. It
/// carries no `package:matrix/matrix.dart` dependency — the SDK `Event` is
/// converted to this type at the conversion boundary (`ReplyPreviewHost` for
/// inline reply previews, `ComposeBar` for compose reply/edit banners) via
/// `ReplyPreviewResolver`.
///
/// All display fields are pre-computed: the body is reply-fallback-stripped and
/// already shows "Unable to decrypt" when the parent event is bad-encrypted.
/// Preview widgets below the boundary consume this model and never touch the
/// Matrix SDK directly.
@immutable
class KoheraReplyPreview {
  const KoheraReplyPreview({
    required this.parentSenderName,
    required this.parentBody,
    required this.parentMessageId,
    this.parentSenderId,
    this.parentFormattedHtml,
  });

  /// The resolved display name of the parent message sender.
  final String parentSenderName;

  /// The display body text (reply fallback stripped, "Unable to decrypt"
  /// if the parent event is bad-encrypted).
  final String parentBody;

  /// Pre-computed formatted HTML body, or `null` if the message is not
  /// HTML-formatted.
  final String? parentFormattedHtml;

  /// The Matrix event ID of the parent/referenced message.
  final String parentMessageId;

  /// The Matrix user ID of the parent sender, used for accent colour
  /// computation in preview banners.
  final String? parentSenderId;

  KoheraReplyPreview copyWith({
    String? parentSenderName,
    String? parentBody,
    String? parentFormattedHtml,
    String? parentMessageId,
    String? parentSenderId,
  }) =>
      KoheraReplyPreview(
        parentSenderName: parentSenderName ?? this.parentSenderName,
        parentBody: parentBody ?? this.parentBody,
        parentFormattedHtml: parentFormattedHtml ?? this.parentFormattedHtml,
        parentMessageId: parentMessageId ?? this.parentMessageId,
        parentSenderId: parentSenderId ?? this.parentSenderId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraReplyPreview &&
          parentMessageId == other.parentMessageId;

  @override
  int get hashCode => parentMessageId.hashCode;

  @override
  String toString() =>
      'KoheraReplyPreview(parentMessageId: $parentMessageId, '
      'parentSenderName: $parentSenderName, parentSenderId: $parentSenderId)';
}

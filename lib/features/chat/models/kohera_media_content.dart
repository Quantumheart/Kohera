import 'package:flutter/foundation.dart';

import 'package:kohera/features/chat/models/kohera_media_type.dart';

/// A Kohera-owned domain model representing a media attachment with
/// pre-computed metadata extracted from a Matrix `Event`.
///
/// This is the display model for media bubble and media viewer widgets. It
/// carries no `package:matrix/matrix.dart` dependency — the SDK `Event` is
/// converted to this type at the conversion boundary (`ChatMessageItem`,
/// `MessageListView`, `SharedMediaSection`) via `MediaContentResolver`.
///
/// Display widgets below the boundary (`ImageBubble`, `VideoBubble`,
/// `AudioBubble`, `FileBubble`, `StickerBubble`, `FullImageView`,
/// `MediaViewerShell`) consume this model and never touch the Matrix SDK
/// directly. Live SDK operations (download, decrypt, URI resolution) are
/// handled by the `MediaController` interface, passed alongside this model.
@immutable
class KoheraMediaContent {
  const KoheraMediaContent({
    required this.mediaType,
    this.mxcUrl,
    this.mimeType,
    this.fileSize,
    this.width,
    this.height,
    this.duration,
    this.fileName,
    this.caption,
    this.thumbnailUrl,
    this.senderName,
    this.senderId,
    this.senderAvatarUrl,
    this.timestamp,
  });

  /// The type of media attachment.
  final KoheraMediaType mediaType;

  /// The `mxc://` URI of the attachment.
  final String? mxcUrl;

  /// MIME type from `content.info.mimetype`.
  final String? mimeType;

  /// File size in bytes from `content.info.size`.
  final int? fileSize;

  /// Image/video width in pixels from `content.info.w`.
  final int? width;

  /// Image/video height in pixels from `content.info.h`.
  final int? height;

  /// Duration in milliseconds from `content.info.duration` (audio/video).
  final int? duration;

  /// The file name (from `event.body`) — used as the download save name.
  final String? fileName;

  /// Caption text (from `event.body`) — same as [fileName] for images.
  final String? caption;

  /// Thumbnail `mxc://` URI from `content.info.thumbnail_url`.
  final String? thumbnailUrl;

  /// Resolved sender display name (for `MediaViewerShell`).
  final String? senderName;

  /// Sender user ID (for `MediaViewerShell`).
  final String? senderId;

  /// Sender avatar `mxc://` URI (for `MediaViewerShell`).
  final String? senderAvatarUrl;

  /// Event timestamp (for `MediaViewerShell`).
  final DateTime? timestamp;

  KoheraMediaContent copyWith({
    KoheraMediaType? mediaType,
    String? mxcUrl,
    String? mimeType,
    int? fileSize,
    int? width,
    int? height,
    int? duration,
    String? fileName,
    String? caption,
    String? thumbnailUrl,
    String? senderName,
    String? senderId,
    String? senderAvatarUrl,
    DateTime? timestamp,
  }) =>
      KoheraMediaContent(
        mediaType: mediaType ?? this.mediaType,
        mxcUrl: mxcUrl ?? this.mxcUrl,
        mimeType: mimeType ?? this.mimeType,
        fileSize: fileSize ?? this.fileSize,
        width: width ?? this.width,
        height: height ?? this.height,
        duration: duration ?? this.duration,
        fileName: fileName ?? this.fileName,
        caption: caption ?? this.caption,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        senderName: senderName ?? this.senderName,
        senderId: senderId ?? this.senderId,
        senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
        timestamp: timestamp ?? this.timestamp,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraMediaContent && mxcUrl == other.mxcUrl;

  @override
  int get hashCode => mxcUrl.hashCode;

  @override
  String toString() =>
      'KoheraMediaContent(mediaType: $mediaType, mxcUrl: $mxcUrl, '
      'fileName: $fileName, fileSize: $fileSize)';
}

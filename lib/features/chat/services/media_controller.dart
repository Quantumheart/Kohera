import 'dart:typed_data';

/// Abstraction over Matrix SDK media operations (download, decrypt,
/// URI resolution, auth headers) so media widgets depend on this interface,
/// not on `package:matrix/matrix.dart`.
///
/// The concrete implementation [SdkMediaController] holds the SDK `Event` and
/// delegates to SDK methods. Display widgets (`ImageBubble`, `VideoBubble`,
/// `AudioBubble`, `FileBubble`, `StickerBubble`, `FullImageView`,
/// `MediaViewerShell`) receive a `MediaController` and call these methods
/// without ever importing the Matrix SDK.
abstract interface class MediaController {
  /// Whether the attachment is encrypted.
  bool get isEncrypted;

  /// The event ID (for caching, player registration, waveform seeding).
  String get eventId;

  /// Whether the message is still being sent (outbox state).
  bool get isPendingSend;

  /// MIME type from the event info (for MediaCache extension resolution).
  String? get mimeType;

  /// Downloads and decrypts the attachment (or its thumbnail).
  ///
  /// Returns the raw bytes. For encrypted attachments this decrypts in memory.
  /// Pass [getThumbnail] as `true` to fetch the thumbnail variant.
  Future<Uint8List> downloadAndDecrypt({bool getThumbnail = false});

  /// Resolves an HTTP URL for the attachment (or its thumbnail).
  ///
  /// Returns `null` if the URL can't be resolved. For unencrypted attachments
  /// this returns a direct HTTP URL with optional auth via [authHeaders]. For
  /// video thumbnails, the implementation includes a fallback that derives a
  /// server-generated thumbnail from the attachment mxc URL.
  ///
  /// Pass [getThumbnail] as `true` for the thumbnail variant. [width] and
  /// [height] request a specific size from the media server.
  Future<String?> getAttachmentUri({
    bool getThumbnail = false,
    int? width,
    int? height,
  });

  /// Auth headers for a resolved media URL (for `Image.network`).
  ///
  /// Returns `null` if the URL is on a federated server (no token leakage to
  /// other homeservers).
  Map<String, String>? authHeaders(String url);
}

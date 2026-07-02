import 'dart:typed_data';

import 'package:kohera/core/utils/media_auth.dart';
import 'package:kohera/features/chat/services/media_controller.dart';
import 'package:matrix/matrix.dart';

/// [MediaController] backed by a Matrix SDK [Event].
///
/// Holds the `Event` and delegates to SDK methods for download, decryption,
/// URI resolution, and auth headers. This is the only media-related class
/// that touches the SDK directly — display widgets depend on the
/// [MediaController] interface, not this implementation.
class SdkMediaController implements MediaController {
  SdkMediaController(this._event);

  final Event _event;

  @override
  bool get isEncrypted => _event.isAttachmentEncrypted;

  @override
  String get eventId => _event.eventId;

  @override
  bool get isPendingSend =>
      _event.status == EventStatus.sending ||
      _event.status == EventStatus.error;

  @override
  String? get mimeType => _event.content
      .tryGet<Map<String, Object?>>('info')
      ?.tryGet<String>('mimetype');

  @override
  Future<Uint8List> downloadAndDecrypt({bool getThumbnail = false}) async {
    final file = await _event.downloadAndDecryptAttachment(
      getThumbnail: getThumbnail,
    );
    return file.bytes;
  }

  @override
  Future<String?> getAttachmentUri({
    bool getThumbnail = false,
    int? width,
    int? height,
  }) async {
    var uri = await _event.getAttachmentUri(
      getThumbnail: getThumbnail,
      width: width?.toDouble() ?? 800.0,
      height: height?.toDouble() ?? 800.0,
    );
    // Fallback: derive a server-generated thumbnail directly from the
    // attachment mxc URL when the event has no explicit thumbnail_url.
    if (uri == null && getThumbnail) {
      final mxc = _event.attachmentMxcUrl;
      if (mxc != null && width != null && height != null) {
        uri = await mxc.getThumbnailUri(
          _event.room.client,
          width: width.toDouble(),
          height: height.toDouble(),
        );
      }
    }
    return uri?.toString();
  }

  @override
  Map<String, String>? authHeaders(String url) =>
      mediaAuthHeaders(_event.room.client, url);
}

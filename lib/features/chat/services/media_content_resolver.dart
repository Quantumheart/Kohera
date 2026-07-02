import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:matrix/matrix.dart';

/// Converts an SDK [Event] into a pre-computed [KoheraMediaContent] for the
/// media bubble and media viewer widget tree.
///
/// This is the conversion boundary for media rendering. Display widgets below
/// the boundary consume [KoheraMediaContent] and never import
/// `package:matrix/matrix.dart`. The companion `SdkMediaController` handles
/// live SDK operations (download, decrypt, URI resolution).
class MediaContentResolver {
  const MediaContentResolver();

  KoheraMediaContent call(Event event) {
    final mediaType = _mediaTypeFor(event);
    final info = event.content.tryGet<Map<String, Object?>>('info');
    final mxcUrl =
        event.content.tryGet<String>('url') ?? event.attachmentMxcUrl?.toString();
    final sender = event.senderFromMemoryOrFallback;

    return KoheraMediaContent(
      mediaType: mediaType,
      mxcUrl: mxcUrl,
      mimeType: info?.tryGet<String>('mimetype'),
      fileSize: info?.tryGet<int>('size'),
      width: info?.tryGet<int>('w'),
      height: info?.tryGet<int>('h'),
      duration: info?.tryGet<int>('duration'),
      fileName: event.body,
      caption: event.body,
      thumbnailUrl: info?.tryGet<String>('thumbnail_url'),
      senderName: sender.calcDisplayname(),
      senderId: event.senderId,
      senderAvatarUrl: sender.avatarUrl?.toString(),
      timestamp: event.originServerTs,
    );
  }

  KoheraMediaType _mediaTypeFor(Event event) {
    if (event.type == EventTypes.Sticker) return KoheraMediaType.sticker;
    return switch (event.messageType) {
      MessageTypes.Image => KoheraMediaType.image,
      MessageTypes.Video => KoheraMediaType.video,
      MessageTypes.Audio => KoheraMediaType.audio,
      MessageTypes.File => KoheraMediaType.file,
      _ => KoheraMediaType.file,
    };
  }
}

import 'dart:async';
import 'dart:ui' as ui show Codec, ImmutableBuffer, TargetImageSize;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// An [ImageProvider] that decodes [Uint8List] image data at a reduced
/// resolution and then **releases the raw bytes** after decoding.
///
/// For encrypted Matrix attachments, [MediaController.downloadAndDecrypt]
/// may return the full-resolution file (not a server-generated thumbnail)
/// when the event has no explicit `thumbnail_url`. Holding those raw bytes
/// in widget state for every visible image bubble caused OOM crashes in
/// media-rich encrypted rooms — the Flutter image cache cap only limits
/// decoded bitmaps, not the raw `Uint8List` held by [MemoryImage].
///
/// This provider uses [eventId] as the [ImageCache] key (not the bytes),
/// so once the [ui.ImmutableBuffer] is created the bytes are nulled out
/// and eligible for garbage collection. The decoded bitmap persists in the
/// image cache. If the cache evicts the entry and the image is requested
/// again, the calling widget will reload from the SDK.
class OneTimeMemoryImage extends ImageProvider<OneTimeMemoryImage> {
  OneTimeMemoryImage({
    required this.eventId,
    required Uint8List bytes,
    this.cacheWidth,
    this.cacheHeight,
  }) : _bytes = bytes;

  final String eventId;
  Uint8List? _bytes;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Future<OneTimeMemoryImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<OneTimeMemoryImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    OneTimeMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: 'OneTimeMemoryImage($eventId)',
    );
  }

  Future<ui.Codec> _loadAsync(
    OneTimeMemoryImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = key._bytes;
    if (bytes == null) {
      throw StateError(
        'OneTimeMemoryImage bytes already released for ${key.eventId}',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    key._bytes = null;
    return decode(
      buffer,
      getTargetSize: key.cacheWidth != null || key.cacheHeight != null
          ? (_, _) => ui.TargetImageSize(
                width: key.cacheWidth,
                height: key.cacheHeight,
              )
          : null,
    );
  }

  @override
  // Equality is based on the immutable eventId, not the mutable _bytes
  // field which is intentionally nulled out after decoding.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      other is OneTimeMemoryImage && eventId == other.eventId;

  @override
  // Equality is based on the immutable eventId, not the mutable _bytes
  // field which is intentionally nulled out after decoding.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => eventId.hashCode;

  @override
  String toString() =>
      'OneTimeMemoryImage(eventId: $eventId, '
      '${_bytes != null ? 'has bytes' : 'bytes released'})';
}

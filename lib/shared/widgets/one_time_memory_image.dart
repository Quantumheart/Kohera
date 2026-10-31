import 'dart:async';
import 'dart:ui' as ui show Codec, ImmutableBuffer, TargetImageSize;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
class OneTimeMemoryImageKey {
  const OneTimeMemoryImageKey(
    this.eventId, {
    this.cacheWidth,
    this.cacheHeight,
  });

  final String eventId;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  bool operator ==(Object other) =>
      other is OneTimeMemoryImageKey &&
      other.eventId == eventId &&
      other.cacheWidth == cacheWidth &&
      other.cacheHeight == cacheHeight;

  @override
  int get hashCode => Object.hash(eventId, cacheWidth, cacheHeight);
}

class OneTimeMemoryImage extends ImageProvider<OneTimeMemoryImageKey> {
  OneTimeMemoryImage({
    required this.eventId,
    Uint8List? bytes,
    this.cacheWidth,
    this.cacheHeight,
  }) : _bytes = bytes;

  final String eventId;
  Uint8List? _bytes;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Future<OneTimeMemoryImageKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<OneTimeMemoryImageKey>(
      OneTimeMemoryImageKey(
        eventId,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
      ),
    );
  }

  @override
  ImageStreamCompleter loadImage(
    OneTimeMemoryImageKey key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: 'OneTimeMemoryImage($eventId)',
    );
  }

  Future<ui.Codec> _loadAsync(
    OneTimeMemoryImageKey key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = _bytes;
    if (bytes == null) {
      throw StateError('OneTimeMemoryImage has no bytes for ${key.eventId}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    _bytes = null;
    try {
      return await decode(
        buffer,
        getTargetSize: key.cacheWidth != null || key.cacheHeight != null
            ? (_, _) => ui.TargetImageSize(
                  width: key.cacheWidth,
                  height: key.cacheHeight,
                )
            : null,
      );
    } catch (_) {
      scheduleMicrotask(
        () => PaintingBinding.instance.imageCache.evict(key),
      );
      rethrow;
    }
  }

  @override
  String toString() =>
      'OneTimeMemoryImage(eventId: $eventId, '
      '${_bytes != null ? 'has bytes' : 'bytes released'})';
}

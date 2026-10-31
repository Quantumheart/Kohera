import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/data/models/kohera_media_content.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/one_time_memory_image.dart';

// coverage:ignore-start

class StickerBubble extends StatefulWidget {
  const StickerBubble({
    required this.media,
    required this.controller,
    required this.isMe,
    super.key,
  });

  final KoheraMediaContent media;
  final MediaController controller;
  final bool isMe;

  @override
  State<StickerBubble> createState() => _StickerBubbleState();
}

class _StickerBubbleState extends State<StickerBubble> {
  static const double _maxSize = 180;

  ImageProvider? _imageProvider;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSticker());
  }

  @override
  void didUpdateWidget(StickerBubble old) {
    super.didUpdateWidget(old);
    if (old.controller.eventId != widget.controller.eventId) {
      _imageProvider = null;
      _imageUrl = null;
      _loading = true;
      unawaited(_loadSticker());
    }
  }

  Future<void> _loadSticker() async {
    try {
      if (widget.controller.isEncrypted) {
        const cacheWidth = 280;
        const cacheHeight = 280;
        final key = OneTimeMemoryImageKey(
          widget.controller.eventId,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
        );
        if (PaintingBinding.instance.imageCache.containsKey(key)) {
          if (mounted) {
            setState(() {
              _imageProvider = OneTimeMemoryImage(
                eventId: widget.controller.eventId,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
              );
              _loading = false;
            });
          }
          return;
        }
        final bytes = await widget.controller.downloadAndDecrypt();
        if (mounted) {
          setState(() {
            _imageProvider = OneTimeMemoryImage(
              eventId: widget.controller.eventId,
              bytes: bytes,
              cacheWidth: cacheWidth,
              cacheHeight: cacheHeight,
            );
            _loading = false;
          });
        }
      } else {
        final uri = await widget.controller.getAttachmentUri(
          width: _maxSize.toInt() * 2,
          height: _maxSize.toInt() * 2,
        );
        if (mounted) {
          setState(() {
            _imageUrl = uri;
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Sticker load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.media.caption ?? widget.media.fileName ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: _maxSize,
              maxWidth: _maxSize,
            ),
            child: _loading
                ? const SizedBox(
                    width: 80,
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _imageProvider != null
                  ? Image(
                      image: _imageProvider!,
                      fit: BoxFit.contain,
                      semanticLabel: body,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                      ),
                    )
                  : _imageUrl != null
                        ? Image.network(
                            _imageUrl!,
                            fit: BoxFit.contain,
                            cacheWidth: 280,
                            cacheHeight: 280,
                            semanticLabel: body,
                            headers:
                                widget.controller.authHeaders(_imageUrl!),
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              size: 48,
                            ),
                          )
                        : const Icon(Icons.broken_image_outlined, size: 48),
          ),
        ],
      ),
    );
  }
}
// coverage:ignore-end

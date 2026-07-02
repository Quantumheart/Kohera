import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/services/media_controller.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/full_image_view.dart';

// coverage:ignore-start

// ── Image bubble (async URI resolution) ──────────────────────

class ImageBubble extends StatefulWidget {
  const ImageBubble({
    required this.media,
    required this.controller,
    required this.avatarResolver,
    super.key,
  });

  final KoheraMediaContent media;
  final MediaController controller;
  final AvatarResolver avatarResolver;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadImage());
  }

  @override
  void didUpdateWidget(ImageBubble old) {
    super.didUpdateWidget(old);
    if (old.controller.eventId != widget.controller.eventId) {
      _imageBytes = null;
      _imageUrl = null;
      _loading = true;
      unawaited(_loadImage());
    }
  }

  Future<void> _loadImage() async {
    try {
      if (widget.controller.isEncrypted) {
        final bytes = await widget.controller.downloadAndDecrypt(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            _loading = false;
          });
        }
      } else {
        final uri = await widget.controller.getAttachmentUri(
          getThumbnail: true,
          width: 280,
          height: 260,
        );
        if (mounted) {
          setState(() {
            _imageUrl = uri;
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Image bubble load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => showFullImageDialog(
        context,
        widget.media,
        widget.controller,
        widget.avatarResolver,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 280),
          child: _loading
              ? Container(
                  height: 80,
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _imageBytes != null
                  ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                  : _imageUrl != null
                      ? Image.network(
                          _imageUrl!,
                          fit: BoxFit.cover,
                          headers: widget.controller.authHeaders(_imageUrl!),
                          errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        )
                      : Container(
                          height: 80,
                          color: cs.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
        ),
      ),
    );
  }
}
// coverage:ignore-end

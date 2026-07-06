import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';


void showFullImageDialog(
  BuildContext context,
  KoheraMediaContent media,
  MediaController controller,
  AvatarResolver avatarResolver,
) {
  showMediaViewer(
    context,
    media: media,
    controller: controller,
    avatarResolver: avatarResolver,
    child: _FullImageContent(media: media, controller: controller),
  );
}

// ── Full image viewer ──────────────────────────────────────────

// coverage:ignore-start
class _FullImageContent extends StatefulWidget {
  const _FullImageContent({required this.media, required this.controller});

  final KoheraMediaContent media;
  final MediaController controller;

  @override
  State<_FullImageContent> createState() => _FullImageContentState();
}

class _FullImageContentState extends State<_FullImageContent> {
  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFullImage());
  }

  Future<void> _loadFullImage() async {
    try {
      if (widget.controller.isEncrypted) {
        final bytes = await widget.controller.downloadAndDecrypt();
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            _loading = false;
          });
        }
      } else {
        final uri = await widget.controller.getAttachmentUri();
        if (mounted) {
          setState(() {
            _imageUrl = uri;
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Full image load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: KoheraLoader());
    }

    final image = _imageBytes != null
        ? Image.memory(_imageBytes!, fit: BoxFit.contain)
        : _imageUrl != null
            ? Image.network(
                _imageUrl!,
                fit: BoxFit.contain,
                headers: widget.controller.authHeaders(_imageUrl!),
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: cs.onSurfaceVariant,
                    size: 48,
                  ),
                ),
              )
            : const Center(child: Text('Failed to load image'));

    return InteractiveViewer(child: image);
  }
}
// coverage:ignore-end

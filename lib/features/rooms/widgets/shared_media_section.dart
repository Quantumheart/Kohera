import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/format_file_size.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/full_image_view.dart';


/// A page of loaded shared media from a room.
class SharedMediaPage {
  const SharedMediaPage({
    required this.items,
    this.nextBatch,
  });

  final List<SharedMediaItem> items;
  final String? nextBatch;
}

/// A single media item loaded from the room's shared media search.
class SharedMediaItem {
  const SharedMediaItem({
    required this.media,
    required this.controller,
  });

  final KoheraMediaContent media;
  final MediaController controller;
}

/// Loads shared media (images, videos, files, audio) from a room via
/// `room.searchEvents()`. This is the SDK boundary — callers pass a
/// [SharedMediaLoader] function, not a `Room`.
typedef SharedMediaLoader = Future<SharedMediaPage> Function({
  required String roomId,
  String? nextBatch,
});

/// Displays a grid of images/videos and a list of files shared in a room.
class SharedMediaSection extends StatefulWidget {
  const SharedMediaSection({
    required this.roomId,
    required this.loader,
    required this.avatarResolver,
    super.key,
  });

  final String roomId;
  final SharedMediaLoader loader;
  final AvatarResolver avatarResolver;

  @override
  State<SharedMediaSection> createState() => _SharedMediaSectionState();
}

class _SharedMediaSectionState extends State<SharedMediaSection> {
  final List<SharedMediaItem> _items = [];
  String? _nextBatch;
  bool _loading = false;
  bool _hasMore = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMedia());
  }

  @override
  void didUpdateWidget(SharedMediaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _generation++;
      _items.clear();
      _nextBatch = null;
      _hasMore = true;
      _loading = false;
      unawaited(_loadMedia());
    }
  }

  Future<void> _loadMedia() async {
    if (_loading) return;
    setState(() => _loading = true);
    final gen = _generation;

    try {
      final page = await widget.loader(
        roomId: widget.roomId,
        nextBatch: _nextBatch,
      );

      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _nextBatch = page.nextBatch;
        _hasMore = page.nextBatch != null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Kohera] Load media failed: $e');
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final images = _items
        .where(
          (i) =>
              i.media.mediaType == KoheraMediaType.image ||
              i.media.mediaType == KoheraMediaType.video,
        )
        .toList();
    final files = _items
        .where(
          (i) =>
              i.media.mediaType == KoheraMediaType.file ||
              i.media.mediaType == KoheraMediaType.audio,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'SHARED MEDIA',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'No shared media yet',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          )
        else ...[
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: images
                    .map(
                      (i) => _MediaThumbnail(
                        media: i.media,
                        controller: i.controller,
                        avatarResolver: widget.avatarResolver,
                      ),
                    )
                    .toList(),
              ),
            ),
          for (final file in files)
            _FileListTile(
              media: file.media,
            ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _loadMedia,
                        child: const Text('Load more'),
                      ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── File list tile ─────────────────────────────────────────────

class _FileListTile extends StatelessWidget {
  const _FileListTile({required this.media});

  final KoheraMediaContent media;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListTile(
      dense: true,
      leading: Icon(
        media.mediaType == KoheraMediaType.audio
            ? Icons.audiotrack_rounded
            : Icons.insert_drive_file_rounded,
        color: cs.onSurfaceVariant,
      ),
      title: Text(
        media.fileName ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        media.fileSize != null ? formatFileSize(media.fileSize!) : '',
        style: tt.bodySmall,
      ),
    );
  }
}

// ── Media thumbnail ────────────────────────────────────────────

class _MediaThumbnail extends StatefulWidget {
  const _MediaThumbnail({
    required this.media,
    required this.controller,
    required this.avatarResolver,
  });

  final KoheraMediaContent media;
  final MediaController controller;
  final AvatarResolver avatarResolver;

  @override
  State<_MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<_MediaThumbnail> {
  Uint8List? _thumbnailBytes;
  String? _thumbnailUrl;
  bool _loading = true;
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loadStarted) {
        _loadStarted = true;
        unawaited(_loadThumbnail());
      }
    });
  }

  Future<void> _loadThumbnail() async {
    try {
      if (widget.controller.isEncrypted) {
        final bytes = await widget.controller.downloadAndDecrypt(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _thumbnailBytes = bytes;
            _loading = false;
          });
        }
      } else {
        final uri = await widget.controller.getAttachmentUri(
          getThumbnail: true,
          width: 200,
          height: 200,
        );
        if (mounted) {
          setState(() {
            _thumbnailUrl = uri;
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Thumbnail load failed: $e');
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
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _thumbnailBytes != null
                  ? Image.memory(_thumbnailBytes!, fit: BoxFit.cover)
                  : _thumbnailUrl != null
                      ? Image.network(
                          _thumbnailUrl!,
                          fit: BoxFit.cover,
                          headers:
                              widget.controller.authHeaders(_thumbnailUrl!),
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : Icon(
                          Icons.image_rounded,
                          color: cs.onSurfaceVariant,
                        ),
        ),
      ),
    );
  }
}

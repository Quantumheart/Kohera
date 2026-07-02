import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/core/utils/format_file_size.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/features/chat/services/media_content_resolver.dart';
import 'package:kohera/features/chat/services/media_controller.dart';
import 'package:kohera/features/chat/services/sdk_media_controller.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/full_image_view.dart';
import 'package:matrix/matrix.dart';

/// Displays a grid of images/videos and a list of files shared in a room.
/// Loads media lazily using room search with pagination.
class SharedMediaSection extends StatefulWidget {
  const SharedMediaSection({required this.room, super.key});

  final Room room;

  @override
  State<SharedMediaSection> createState() => _SharedMediaSectionState();
}

class _SharedMediaSectionState extends State<SharedMediaSection> {
  final List<Event> _mediaEvents = [];
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
    if (oldWidget.room.id != widget.room.id) {
      _generation++;
      _mediaEvents.clear();
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
      final result = await widget.room.searchEvents(
        searchFunc: (event) {
          final mt = event.messageType;
          return mt == MessageTypes.Image ||
              mt == MessageTypes.Video ||
              mt == MessageTypes.File ||
              mt == MessageTypes.Audio;
        },
        nextBatch: _nextBatch,
        limit: 20,
      );

      if (!mounted || gen != _generation) return;
      setState(() {
        _mediaEvents.addAll(result.events);
        _nextBatch = result.nextBatch;
        _hasMore = result.nextBatch != null;
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

    final images = _mediaEvents
        .where((e) =>
            e.messageType == MessageTypes.Image ||
            e.messageType == MessageTypes.Video,)
        .toList();
    final files = _mediaEvents
        .where((e) =>
            e.messageType == MessageTypes.File ||
            e.messageType == MessageTypes.Audio,)
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
        if (_loading && _mediaEvents.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_mediaEvents.isEmpty)
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
          // Image/video grid
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
                    .map((e) => _MediaThumbnail(
                          media: const MediaContentResolver()(e),
                          controller: SdkMediaController(e),
                          avatarResolver: ClientAvatarResolver(
                            widget.room.client,
                          ),
                        ),)
                    .toList(),
              ),
            ),

          // File list
          for (final file in files)
            _FileListTile(
              media: const MediaContentResolver()(file),
            ),

          // Load more
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
    // Defer loading to avoid firing all thumbnails simultaneously.
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
                          errorBuilder: (_, __, ___) => Icon(
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

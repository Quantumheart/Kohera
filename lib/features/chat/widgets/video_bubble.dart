import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_player_factory.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/utils/format_duration.dart';
import 'package:kohera/core/utils/format_file_size.dart';
import 'package:kohera/core/utils/media_cache.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/widgets/full_video_view.dart';
import 'package:kohera/features/chat/widgets/inline_video_controls.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:provider/provider.dart';


// ── Video bubble (thumbnail → inline player) ──────────────────

const _maxFileSizeBytes = 104857600;
const double _maxBubbleWidth = 280;
const double _maxBubbleHeight = 260;
const double _defaultAspectRatio = 16 / 9;

class VideoBubble extends StatefulWidget {
  const VideoBubble({
    required this.media,
    required this.controller,
    required this.isMe,
    required this.avatarResolver,
    super.key,
  });

  final KoheraMediaContent media;
  final MediaController controller;
  final bool isMe;
  final AvatarResolver avatarResolver;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

enum _VideoState { initial, loadingThumb, loadingVideo, playing, error }

class _VideoBubbleState extends State<VideoBubble>
    with SingleTickerProviderStateMixin {
  _VideoState _state = _VideoState.initial;
  Uint8List? _thumbBytes;
  String? _thumbUrl;
  bool _thumbFailed = false;
  KoheraVideoController? _videoController;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final MediaPlaybackService _playbackService;
  final List<StreamSubscription<dynamic>> _subs = [];
  AnimationController? _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_shimmer!.repeat(reverse: true));
    unawaited(_loadThumbnail());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackService = context.read<MediaPlaybackService>();
  }

  @override
  void dispose() {
    _shimmer?.dispose();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    if (_videoController != null) {
      _playbackService.unregisterPlayer(widget.controller.eventId);
      unawaited(_videoController!.dispose());
    }
    super.dispose();
  }

  bool get _tooLarge {
    final size = widget.media.fileSize;
    return size != null && size > _maxFileSizeBytes;
  }

  double get _aspectRatio {
    final w = widget.media.width;
    final h = widget.media.height;
    if (w == null || h == null || w <= 0 || h <= 0) return _defaultAspectRatio;
    return w / h;
  }

  Size get _boxSize {
    final ratio = _aspectRatio;
    var width = _maxBubbleWidth;
    var height = _maxBubbleWidth / ratio;
    if (height > _maxBubbleHeight) {
      height = _maxBubbleHeight;
      width = _maxBubbleHeight * ratio;
    }
    return Size(width, height);
  }

  Future<void> _loadThumbnail() async {
    setState(() {
      _state = _VideoState.loadingThumb;
      _thumbFailed = false;
    });
    try {
      if (widget.controller.isEncrypted) {
        final bytes = await widget.controller.downloadAndDecrypt(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _thumbBytes = bytes;
            _state = _VideoState.initial;
          });
        }
      } else {
        final box = _boxSize;
        final uri = await widget.controller.getAttachmentUri(
          getThumbnail: true,
          width: box.width.round(),
          height: box.height.round(),
        );
        if (mounted) {
          setState(() {
            _thumbUrl = uri;
            _state = _VideoState.initial;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Video thumbnail load failed: $e');
      if (mounted) {
        setState(() {
          _thumbFailed = true;
          _state = _VideoState.initial;
        });
      }
    }
  }

  Future<void> _initPlayer() async {
    if (_tooLarge) return;
    if (_state == _VideoState.loadingVideo ||
        _state == _VideoState.playing) {
      return;
    }
    setState(() => _state = _VideoState.loadingVideo);

    try {
      final media = await MediaCache.resolve(widget.controller);
      if (!mounted) return;

      _videoController = createKoheraVideoController();

      _subs.add(_videoController!.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),);
      _subs.add(_videoController!.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),);
      _subs.add(_videoController!.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),);
      _subs.add(_videoController!.completed.listen((completed) {
        if (completed && mounted) {
          unawaited(_videoController!.seek(Duration.zero));
          unawaited(_videoController!.pause());
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      }),);

      _playbackService.registerPlayer(widget.controller.eventId, _videoController!);
      await _videoController!.open(media);
      if (!mounted) return;

      setState(() => _state = _VideoState.playing);
    } catch (e) {
      debugPrint('[Kohera] Video playback failed: $e');
      if (mounted) setState(() => _state = _VideoState.error);
    }
  }

  void _retry() {
    if (_state == _VideoState.loadingVideo) return;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    if (_videoController != null) unawaited(_videoController!.dispose());
    _videoController = null;
    unawaited(_initPlayer());
  }

  void _openFullscreen() {
    final controller = _videoController;
    if (controller == null) return;
    showFullVideoDialog(
      context,
      media: widget.media,
      mediaController: widget.controller,
      avatarResolver: widget.avatarResolver,
      controller: controller,
      isPlaying: _isPlaying,
      position: _position,
      duration: _duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = widget.isMe ? cs.onPrimary : cs.onSurface;

    if (_tooLarge) {
      return _buildFileFallback(foreground, tt);
    }

    if (_state == _VideoState.playing && _videoController != null) {
      return _buildInlinePlayer();
    }

    return _buildThumbnailPreview(cs, foreground);
  }

  Widget _buildThumbnailPreview(ColorScheme cs, Color foreground) {
    final durationMs = widget.media.duration;
    final durationLabel = durationMs != null
        ? formatDuration(Duration(milliseconds: durationMs))
        : null;

    final box = _boxSize;
    final Widget thumb;
    if (_state == _VideoState.loadingThumb) {
      thumb = _buildSkeleton(cs);
    } else if (_thumbFailed) {
      thumb = _placeholderThumb(cs);
    } else if (_thumbBytes != null && _thumbBytes!.isNotEmpty) {
      thumb = Image.memory(
        _thumbBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _onImageError(cs),
      );
    } else if (_thumbUrl != null) {
      thumb = Image.network(
        _thumbUrl!,
        fit: BoxFit.cover,
        headers: widget.controller.authHeaders(_thumbUrl!),
        errorBuilder: (_, _, _) => _onImageError(cs),
      );
    } else {
      thumb = _placeholderThumb(cs);
    }

    final loading =
        _state == _VideoState.loadingThumb || _state == _VideoState.loadingVideo;

    return GestureDetector(
      onTap: loading
          ? null
          : _state == _VideoState.error
              ? _retry
              : _initPlayer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              thumb,
              if (_state == _VideoState.loadingVideo)
                const CircularProgressIndicator(strokeWidth: 2)
              else if (_state == _VideoState.error)
                Icon(Icons.error_outline_rounded,
                    size: 40, color: cs.error,)
              else if (!loading)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              if (_thumbFailed && !loading)
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filled(
                    onPressed: _loadThumbnail,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(4),
                      minimumSize: const Size(28, 28),
                    ),
                  ),
                ),
              if (durationLabel != null)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                    ),
                    child: Text(
                      durationLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlinePlayer() {
    final controller = _videoController;
    if (controller == null) return const SizedBox.shrink();
    final box = _boxSize;
    return ClipRRect(
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      child: SizedBox(
        width: box.width,
        height: box.height,
        child: controller.buildView(
          controlsOverlay: InlineVideoControls(
            controller: controller,
            isPlaying: _isPlaying,
            position: _position,
            duration: _duration,
            onOpenFullscreen: _openFullscreen,
          ),
        ),
      ),
    );
  }


  Widget _buildFileFallback(Color foreground, TextTheme tt) {
    final size = widget.media.fileSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam_rounded,
            size: 28, color: foreground.withValues(alpha: 0.7),),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.media.fileName ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w500),
              ),
              if (size != null)
                Text(
                  formatFileSize(size),
                  style: tt.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholderThumb(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.videocam_rounded, size: 40)),
    );
  }

  Widget _buildSkeleton(ColorScheme cs) {
    final shimmer = _shimmer;
    if (shimmer == null) return _placeholderThumb(cs);
    return AnimatedBuilder(
      animation: shimmer,
      builder: (context, _) {
        final t = shimmer.value.clamp(0.0, 1.0);
        final alpha = 0.35 + 0.30 * t;
        return Container(
          key: const ValueKey('videoSkeleton'),
          color: cs.surfaceContainerHighest.withValues(alpha: alpha),
        );
      },
    );
  }

  Widget _onImageError(ColorScheme cs) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _thumbFailed = true);
    });
    return _placeholderThumb(cs);
  }
}

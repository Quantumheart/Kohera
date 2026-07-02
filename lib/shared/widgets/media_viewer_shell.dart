import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/media_cache_io.dart'
    if (dart.library.js_interop) 'package:kohera/core/utils/media_cache_web.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/services/media_controller.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

// ── Shared fullscreen media viewer shell ─────────────────────

void showMediaViewer(
  BuildContext context, {
  required KoheraMediaContent media,
  required MediaController controller,
  required AvatarResolver avatarResolver,
  required Widget child,
}) {
  unawaited(showGeneralDialog(
    context: context,
    barrierColor: Colors.black,
    barrierDismissible: true,
    barrierLabel: 'Close media',
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (ctx, _, __) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: MediaViewerShell(
          media: media,
          controller: controller,
          avatarResolver: avatarResolver,
          child: child,
        ),
      ),
    ),
  ),);
}

class MediaViewerShell extends StatefulWidget {
  const MediaViewerShell({
    required this.media,
    required this.controller,
    required this.avatarResolver,
    required this.child,
    super.key,
  });

  final KoheraMediaContent media;
  final MediaController controller;
  final AvatarResolver avatarResolver;
  final Widget child;

  @override
  State<MediaViewerShell> createState() => _MediaViewerShellState();
}

class _MediaViewerShellState extends State<MediaViewerShell> {
  bool _barVisible = true;
  bool _downloading = false;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _barVisible = false);
    });
  }

  void _toggleBar() {
    setState(() => _barVisible = !_barVisible);
    if (_barVisible) _startAutoHideTimer();
  }

  Future<void> _download() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);

    try {
      final bytes = await widget.controller.downloadAndDecrypt();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Kohera',
        fileName: widget.media.fileName,
        bytes: bytes,
      );

      if (path != null && bytes.isNotEmpty) {
        await File(path).writeAsBytes(bytes);
        scaffold.showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      debugPrint('[Kohera] Media download failed: $e');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Failed to save')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleBar,
            child: widget.child,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _barVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_barVisible,
              child: SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        avatarResolver: widget.avatarResolver,
                        avatarUrl: widget.media.senderAvatarUrl,
                        userId: widget.media.senderId ?? '',
                        displayname: widget.media.senderName ?? '',
                        size: 32,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.media.senderName ??
                                  widget.media.senderId ??
                                  '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              formatRelativeTimestamp(
                                widget.media.timestamp ?? DateTime.now(),
                              ),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_downloading) const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ) else IconButton(
                              icon: const Icon(Icons.download_rounded),
                              color: Colors.white,
                              onPressed: _download,
                            ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

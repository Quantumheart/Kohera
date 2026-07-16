import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/media_cache_io.dart'
    if (dart.library.js_interop) 'package:kohera/core/utils/media_cache_web.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';


// ── Shared fullscreen media viewer shell ─────────────────────

class MediaViewerBarVisibility extends ValueNotifier<bool> {
  MediaViewerBarVisibility([super.value = true]);

  void show() {
    if (value) {
      notifyListeners();
    } else {
      value = true;
    }
  }
}

void showMediaViewer(
  BuildContext context, {
  required KoheraMediaContent media,
  required MediaController controller,
  required AvatarResolver avatarResolver,
  required Widget child,
  MediaViewerBarVisibility? barVisibility,
}) {
  final bar = barVisibility ?? MediaViewerBarVisibility();
  unawaited(showGeneralDialog(
    context: context,
    barrierColor: Colors.black,
    barrierDismissible: true,
    barrierLabel: 'Close media',
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (ctx, _, _) => Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: MediaViewerShell(
            media: media,
            controller: controller,
            avatarResolver: avatarResolver,
            barVisibility: bar,
            child: child,
          ),
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
    required this.barVisibility,
    required this.child,
    super.key,
  });

  final KoheraMediaContent media;
  final MediaController controller;
  final AvatarResolver avatarResolver;
  final MediaViewerBarVisibility barVisibility;
  final Widget child;

  @override
  State<MediaViewerShell> createState() => _MediaViewerShellState();
}

class _MediaViewerShellState extends State<MediaViewerShell>
    with SingleTickerProviderStateMixin {
  bool _downloading = false;
  Timer? _autoHideTimer;

  static const _autoHideDelay = Duration(seconds: 4);
  static const _dismissDistance = 120.0;
  static const _dismissVelocity = 500.0;
  static const _maxDrag = 400.0;

  late final MediaViewerBarVisibility _bar;
  Offset _dragOffset = Offset.zero;
  late final AnimationController _snapBack;
  Animation<Offset>? _snapAnim;

  @override
  void initState() {
    super.initState();
    _bar = widget.barVisibility;
    _bar.addListener(_onBarChanged);
    _startAutoHideTimer();
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _snapBack.addListener(() {
      if (_snapAnim != null) setState(() => _dragOffset = _snapAnim!.value);
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _bar.removeListener(_onBarChanged);
    _snapBack.dispose();
    super.dispose();
  }

  void _onBarChanged() {
    if (!mounted) return;
    if (_bar.value) {
      _startAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
    }
    setState(() {});
  }

  void _onVerticalDragStart(DragStartDetails _) {
    _snapBack.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final ny = (_dragOffset.dy + delta).clamp(0.0, _maxDrag);
    if (ny != _dragOffset.dy) {
      setState(() => _dragOffset = Offset(0, ny));
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset.dy >= _dismissDistance || velocity >= _dismissVelocity) {
      Navigator.of(context).pop();
      return;
    }
    _snapAnim = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(_snapBack);
    _snapBack.reset();
    unawaited(_snapBack.forward());
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_autoHideDelay, () {
      if (mounted) _bar.value = false;
    });
  }

  void _toggleBar() {
    _bar.value = !_bar.value;
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
    final opacity =
        (1 - (_dragOffset.dy / 600).clamp(0.0, 1.0)).clamp(0.3, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: _dragOffset,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleBar,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: widget.child,
              ),
            ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _bar.value ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_bar.value,
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
        ),
      ),
    );
  }
}

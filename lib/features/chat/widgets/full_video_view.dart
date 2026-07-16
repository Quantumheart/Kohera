import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';
import 'package:kohera/shared/widgets/video_fullscreen_controls.dart';

// coverage:ignore-start

// ── Fullscreen video dialog ───────────────────────────────────

void showFullVideoDialog(
  BuildContext context, {
  required KoheraMediaContent media,
  required MediaController mediaController,
  required AvatarResolver avatarResolver,
  required KoheraVideoController controller,
  bool isPlaying = false,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
}) {
  final barVisibility = MediaViewerBarVisibility();
  showMediaViewer(
    context,
    media: media,
    controller: mediaController,
    avatarResolver: avatarResolver,
    child: controller.buildView(
      controlsOverlay: VideoFullscreenControls(
        controller: controller,
        barVisibility: barVisibility,
        initialIsPlaying: isPlaying,
        initialPosition: position,
        initialDuration: duration,
      ),
    ),
  );
}
// coverage:ignore-end

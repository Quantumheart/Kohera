import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// coverage:ignore-start

// ── Fullscreen video dialog ───────────────────────────────────

void showFullVideoDialog(
  BuildContext context, {
  required KoheraMediaContent media,
  required MediaController mediaController,
  required AvatarResolver avatarResolver,
  required Player player,
  required VideoController controller,
}) {
  showMediaViewer(
    context,
    media: media,
    controller: mediaController,
    avatarResolver: avatarResolver,
    child: Video(controller: controller),
  );
}
// coverage:ignore-end

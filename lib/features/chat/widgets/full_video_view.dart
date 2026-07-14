import 'package:flutter/material.dart';
import 'package:kohera/core/media/video_media_player.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';

// coverage:ignore-start

// ── Fullscreen video dialog ───────────────────────────────────

void showFullVideoDialog(
  BuildContext context, {
  required KoheraMediaContent media,
  required MediaController mediaController,
  required AvatarResolver avatarResolver,
  required VideoMediaPlayer player,
}) {
  showMediaViewer(
    context,
    media: media,
    controller: mediaController,
    avatarResolver: avatarResolver,
    child: player.buildView(),
  );
}
// coverage:ignore-end

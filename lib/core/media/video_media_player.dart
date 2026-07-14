import 'package:flutter/widgets.dart';
import 'package:kohera/core/media/media_player.dart';

// ── Video-capable media player ────────────────────────────────

abstract class VideoMediaPlayer extends MediaPlayer {
  Widget buildView();
}

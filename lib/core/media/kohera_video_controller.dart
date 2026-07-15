import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_player.dart';

// ── Platform-agnostic video controller ────────────────────────
//
// A KoheraVideoController is-a KoheraPlayer (play/pause/seek/streams) and
// additionally renders a video surface widget via [buildView]. Inline bubbles
// pass a [controlsOverlay] to render custom controls on top of the surface;
// fullscreen passes null to use the backend's default controls.

abstract class KoheraVideoController implements KoheraPlayer {
  Widget buildView({Widget? controlsOverlay});
}

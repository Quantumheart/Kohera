import 'package:kohera/core/media/kohera_player.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/media/media_kit/media_kit_kohera_player.dart';
import 'package:kohera/core/media/media_kit/media_kit_kohera_video_controller.dart';

// ── Player/video-controller factory (web) ─────────────────────
//
// Web media playback is out of scope (see #784/#611). media_kit is used as a
// compile-safe placeholder; runtime playback is unsupported without
// media_kit_libs_video_web.

KoheraPlayer createKoheraPlayer() => MediaKitKoheraPlayer();

KoheraVideoController createKoheraVideoController() =>
    MediaKitKoheraVideoController();

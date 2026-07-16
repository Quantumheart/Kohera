import 'package:kohera/core/media/kohera_player.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/media/media_kit/media_kit_kohera_player.dart';
import 'package:kohera/core/media/web/web_kohera_video_controller.dart';

// ── Player/video-controller factory (web) ─────────────────────
//
// Audio playback on web is out of scope (see #784/#611); media_kit is used as
// a compile-safe placeholder for the audio player. Video uses the video_player
// HTML5 <video> backend with blob: object URLs for decrypted bytes.

KoheraPlayer createKoheraPlayer() => MediaKitKoheraPlayer();

KoheraVideoController createKoheraVideoController() =>
    WebKoheraVideoController();

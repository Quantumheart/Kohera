import 'dart:io' show Platform;

import 'package:kohera/core/media/kohera_player.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/media/media_kit/media_kit_kohera_player.dart';
import 'package:kohera/core/media/media_kit/media_kit_kohera_video_controller.dart';
import 'package:kohera/core/media/mobile/mobile_kohera_player.dart';
import 'package:kohera/core/media/mobile/mobile_kohera_video_controller.dart';

// ── Player/video-controller factory (native) ──────────────────
//
// media_kit on desktop, video_player/just_audio on iOS/Android.

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

KoheraPlayer createKoheraPlayer() =>
    _isMobile ? MobileKoheraPlayer() : MediaKitKoheraPlayer();

KoheraVideoController createKoheraVideoController() => _isMobile
    ? MobileKoheraVideoController()
    : MediaKitKoheraVideoController();

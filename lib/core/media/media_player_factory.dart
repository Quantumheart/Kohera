import 'package:flutter/foundation.dart';
import 'package:kohera/core/media/android_audio_player.dart';
import 'package:kohera/core/media/ios_audio_player.dart';
import 'package:kohera/core/media/media_kit_player.dart';
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/video_media_player.dart';
import 'package:kohera/core/media/video_player_media_player.dart';
import 'package:kohera/core/utils/platform_info.dart';

// ── Platform player factory ───────────────────────────────────

class MediaPlayerFactory {
  MediaPlayerFactory._();

  static MediaPlayer createAudio() {
    if (kIsWeb || isNativeLinux || isNativeWindows || isNativeMacOS) {
      return MediaKitPlayer();
    }
    if (isNativeAndroid) return AndroidAudioPlayer();
    if (isNativeIOS) return IosAudioPlayer();
    return MediaKitPlayer();
  }

  static VideoMediaPlayer createVideo() {
    if (kIsWeb || isNativeLinux || isNativeWindows || isNativeMacOS) {
      return MediaKitPlayer();
    }
    if (isNativeAndroid || isNativeIOS) return VideoPlayerMediaPlayer();
    return MediaKitPlayer();
  }
}

# Platform Media Player Abstraction — Design

Issue #611: drop bundled libmpv from Android APK and iOS IPA. Platform
players per-OS, media_kit desktop/web only.

## Platform matrix

| Platform | Video | Audio (MP3/AAC/WAV) | Audio (Ogg/Opus) | Ringtone (MP3, loop) |
|---|---|---|---|---|
| Linux / Windows / macOS | media_kit `Video` | media_kit `Player` | media_kit `Player` | media_kit `Player` |
| Web | media_kit (web) | media_kit (web) | media_kit (web) | media_kit (web) |
| Android | `video_player` (ExoPlayer) | `just_audio` | `just_audio` (ExoPlayer Opus) | `just_audio` `LoopingAudioSource` |
| iOS | `video_player` (AVPlayer) | `just_audio` (AVAudioPlayer) | `ogg_opus_player` (native Opus decoder) | `just_audio` `LoopingAudioSource` |

### Known limitations (accepted)

- **iOS VP9/WebM video**: AVPlayer cannot play. Falls to "can't play"
  error state — matches issue's accepted trade-off.
- **iOS Ogg/Opus via `ogg_opus_player`**: native Opus decoder produces sound.
  No seek API (`canSeek=false`; audio_bubble disables waveform drag). This is
  the proven-audible route — AVPlayer parses Opus-in-CAF but emits no audio,
  so the CAF remux approach was abandoned.
- iOS Opus duration: `ogg_opus_player` exposes no duration stream; audio_bubble
  shows the event-metadata duration (`widget.media.duration`) for the initial
  label and `canSeek=false`.

## Abstraction

### `ResolvedMedia` (replaces media_kit `Media`)

`lib/core/media/resolved_media.dart`

```dart
class ResolvedMedia {
  const ResolvedMedia({this.filePath, this.bytes, this.mimeType});
  final String? filePath;   // native: temp file path after decrypt
  final Uint8List? bytes;   // web: in-memory bytes
  final String? mimeType;   // for impl routing (ogg/opus → ogg_opus_player)
}
```

`MediaCache.resolve` returns `ResolvedMedia` instead of `Media`.

### `MediaPlayer` interface

`lib/core/media/media_player.dart`

```dart
abstract class MediaPlayer {
  // Streams (backed by StreamControllers in each impl, normalized from
  // platform-specific listenables/channels).
  Stream<bool> get onPlayingChanged;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<bool> get onCompleted;

  // Sync getters (latest snapshot).
  bool get isPlaying;
  Duration get position;
  Duration get duration;
  bool get canSeek;          // false for ogg_opus_player

  Future<void> open(ResolvedMedia media);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);  // no-op if !canSeek
  void setLoopMode(bool loop);
  Future<void> dispose();
}
```

### `VideoMediaPlayer` interface

`lib/core/media/video_media_player.dart`

```dart
abstract class VideoMediaPlayer extends MediaPlayer {
  /// Platform video surface widget (media_kit `Video` or `VideoPlayer`).
  /// Caller overlays its own controls.
  Widget buildView();
}
```

### `MediaPlayerFactory`

`lib/core/media/media_player_factory.dart`

```dart
class MediaPlayerFactory {
  static MediaPlayer createAudio();
  static VideoMediaPlayer createVideo();
}
```

Selection:

- `createAudio()`:
  - `Platform.isLinux || isWindows || isMacOS || kIsWeb` → `MediaKitPlayer`
  - `Platform.isAndroid` → `AndroidAudioPlayer` (just_audio)
  - `Platform.isIOS` → `IosAudioPlayer` (just_audio; routes Ogg/Opus to
    `ogg_opus_player` based on `ResolvedMedia.mimeType`)
- `createVideo()`:
  - desktop/web → `MediaKitVideoPlayer` (media_kit `Video`)
  - Android → `AndroidVideoPlayer` (`video_player`)
  - iOS → `IosVideoPlayer` (`video_player`)

## Implementations

### `MediaKitPlayer` / `MediaKitVideoPlayer` (desktop + web)

- Wraps media_kit `Player`.
- `VideoMediaPlayer.buildView()` → `Video(controller: VideoController(player))`.
- `open()` → `player.open(Media(filePath) | Media.memory(bytes))`.
- Streams map 1:1 from `player.stream.*`.
- `setLoopMode` → `setPlaylistMode(PlaylistMode.loop | none)`.
- Preserves current behavior exactly (web included).

### `AndroidAudioPlayer` (just_audio)

- Wraps `AudioPlayer`.
- `open()` → `setAudioSource(FileSource(filePath))` (or
  `BytesAudioSource` for web fallback, though Android never uses bytes).
- Streams from `player.playerStateStream`, `positionStream`,
  `durationStream`, `processingStateStream` (completed = `completed`).
- `setLoopMode` → `setLoopMode(LoopMode.one)` +
  `LoopingAudioSource` for asset ringtones.

### `AndroidVideoPlayer` (video_player)

- Wraps `VideoPlayerController.file(File(path))`.
- `buildView()` → `VideoPlayer(controller)`.
- Streams from `controller.value` (`isPlaying`, `position`, `duration`).

### `IosAudioPlayer` (just_audio + ogg_opus_player)

- MIME routing in `open()`:
  - `audio/ogg` | `audio/opus` → `ogg_opus_player` (native Opus decoder,
    guaranteed audible). `canSeek=false`; position polled via a 100 ms timer;
    loop = manual restart on `ended`.
  - else → `just_audio` `AudioPlayer` (MP3/AAC/WAV, seekable).
- `just_audio` path pauses + seeks to zero on `ProcessingState.completed` to
  prevent looping (just_audio keeps `playWhenReady` after completed).
- Audio session configured to playback (`.music()`) + activated, so messages
  are audible even on silent and route to the speaker.
- Streams/loop reuse the same `just_audio` plumbing as `AndroidAudioPlayer`.

### `IosVideoPlayer` (video_player)

- Same as `AndroidVideoPlayer`. AVPlayer backend.

## Migration impact per file

### `media_cache.dart`
- Remove `media_kit` import.
- `resolve()` returns `Future<ResolvedMedia>` (was `Future<Media>`).
- `_bytesToMedia` writes file, returns `ResolvedMedia(filePath: path, mimeType:)`.
- Web: `ResolvedMedia(bytes: bytes, mimeType:)`.

### `media_playback_service.dart`
- `registerPlayer(String eventId, MediaPlayer player)`.
- `_activePlayer` type → `MediaPlayer?`.
- Only calls `pause()` — unchanged semantics.

### `video_bubble.dart`
- `MediaPlayerFactory.createVideo()` → `VideoMediaPlayer`.
- `_player` type → `VideoMediaPlayer?` (drop `VideoController`).
- Inline player → `_player!.buildView()` wrapped in GestureDetector
  overlay (current custom controls preserved).
- Fullscreen handoff → `showFullVideoDialog(context, ..., player: _player!)`.
- `registerPlayer` passes `MediaPlayer`.

### `full_video_view.dart`
- Takes `VideoMediaPlayer player` instead of `Player`+`VideoController`.
- `child: player.buildView()`.

### `audio_bubble.dart`
- `MediaPlayerFactory.createAudio()` → `MediaPlayer`.
- Streams → `onPlayingChanged/onPositionChanged/onDurationChanged/onCompleted`.
- `seek` guarded by `canSeek` — disable waveform drag when false.

### `ringtone_service.dart`
- `MediaPlayerFactory.createAudio()` for each player pool.
- `open(ResolvedMedia(isAsset...))` — but ResolvedMedia has no asset flag.
  Ringtone opens asset paths. Add `assetPath` to `ResolvedMedia` OR
  dedicated `openAsset(String)` method on `MediaPlayer`.
  **Decision: add `Future<void> openAsset(String assetPath)` to
  `MediaPlayer`** — cleaner than overloading `ResolvedMedia`. media_kit
  uses `Media('asset:///...')`, just_audio uses `AssetSource`.
- `setLoopMode(true)` replaces `setPlaylistMode(PlaylistMode.loop)`.

### `main.dart`
- `MediaKit.ensureInitialized()` guarded:
  `if (Platform.isLinux || isWindows || isMacOS || kIsWeb) MediaKit.ensureInitialized();`
  No-op on Android/iOS.

### `voice_recording_mixin.dart`
- Unchanged — only calls `pauseActive()`.

## Test impact

- `audio_bubble_test.mocks.dart` / `video_bubble_test.mocks.dart`:
  `registerPlayer` signature changes `Player` → `MediaPlayer`. Regenerate
  via `build_runner`.
- `media_cache_test.dart`: unaffected (eviction only).
- `FakeRingtoneService`: unaffected (fakes the service, not the player).
- `e2e/chat_screen_test.dart`: `MediaPlaybackService` provider unchanged.
- New: `media_player_factory_test.dart`, impl unit tests with fakes.

## File layout (new)

```
lib/core/media/
  resolved_media.dart
  media_player.dart
  video_media_player.dart
  media_player_factory.dart
  media_kit_player.dart          (desktop + web, audio + video)
  android_audio_player.dart      (just_audio)
  android_video_player.dart      (video_player)
  ios_audio_player.dart          (just_audio + ogg_opus_player)
  ios_video_player.dart          (video_player)
```

## Open questions resolved

- **Asset open**: `openAsset(String)` method on `MediaPlayer` (not
  `ResolvedMedia` flag). Keeps `ResolvedMedia` for decrypted content only.
- **Web**: stays on media_kit (has web backend). Out of scope per issue.
- **iOS Opus seek**: restored via Ogg→CAF remux (`ogg_caf_converter`, pure
  Dart). `canSeek=true`. No native libopus needed.
- **iOS Opus duration**: CAF packet table `numberValidFrames` → AVAudioPlayer
  reports duration via `just_audio` `durationStream`.
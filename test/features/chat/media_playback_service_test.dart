import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/resolved_media.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';

class FakeMediaPlayer implements MediaPlayer {
  int pauseCount = 0;
  bool _playing = false;

  @override
  Stream<bool> get onPlayingChanged => const Stream.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
  @override
  Stream<Duration> get onDurationChanged => const Stream.empty();
  @override
  Stream<bool> get onCompleted => const Stream.empty();

  @override
  bool get isPlaying => _playing;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  bool get canSeek => true;

  @override
  Future<void> open(ResolvedMedia media) async {}
  @override
  Future<void> openAsset(String assetPath) async {}
  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
    pauseCount++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  void setLoopMode(bool loop) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaPlaybackService', () {
    test('registerPlayer pauses previous active player', () async {
      final service = MediaPlaybackService();
      final a = FakeMediaPlayer();
      final b = FakeMediaPlayer();

      service.registerPlayer('event-a', a);
      expect(service.activeEventId, 'event-a');

      service.registerPlayer('event-b', b);
      expect(service.activeEventId, 'event-b');
      expect(a.pauseCount, 1);
      expect(b.pauseCount, 0);

      service.dispose();
    });

    test('registerPlayer same event does not pause', () async {
      final service = MediaPlaybackService();
      final a = FakeMediaPlayer();

      service.registerPlayer('event-a', a);
      service.registerPlayer('event-a', a);
      expect(a.pauseCount, 0);

      service.dispose();
    });

    test('unregisterPlayer clears active', () async {
      final service = MediaPlaybackService();
      final a = FakeMediaPlayer();

      service.registerPlayer('event-a', a);
      service.unregisterPlayer('event-a');
      expect(service.activeEventId, isNull);

      service.dispose();
    });

    test('unregisterPlayer different event is no-op', () async {
      final service = MediaPlaybackService();
      final a = FakeMediaPlayer();

      service.registerPlayer('event-a', a);
      service.unregisterPlayer('event-b');
      expect(service.activeEventId, 'event-a');

      service.dispose();
    });

    test('pauseActive pauses current player', () async {
      final service = MediaPlaybackService();
      final a = FakeMediaPlayer();

      service.registerPlayer('event-a', a);
      service.pauseActive();
      expect(a.pauseCount, 1);

      service.dispose();
    });
  });
}

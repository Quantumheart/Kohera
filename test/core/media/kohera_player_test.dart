import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_player.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';

class _FakeKoheraPlayer implements KoheraPlayer {
  _FakeKoheraPlayer();
  int pauseCount = 0;
  int playCount = 0;
  int stopCount = 0;
  int seekCount = 0;
  int loopCount = 0;
  int openCount = 0;
  bool disposed = false;

  @override
  Future<void> open(KoheraMediaSource source) async => openCount++;

  @override
  Future<void> play() async => playCount++;

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> seek(Duration position) async => seekCount++;

  @override
  Future<void> setLoop(bool loop) async => loopCount++;

  @override
  Stream<bool> get playing => const Stream<bool>.empty();

  @override
  Stream<Duration> get position => const Stream<Duration>.empty();

  @override
  Stream<Duration> get duration => const Stream<Duration>.empty();

  @override
  Stream<bool> get completed => const Stream<bool>.empty();

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KoheraMediaSource', () {
    test('file source holds path', () {
      const source = KoheraFileSource('/tmp/a.ogg');
      expect(source.path, '/tmp/a.ogg');
      expect(source, isA<KoheraFileSource>());
    });

    test('bytes source holds bytes and mime type', () {
      final source = KoheraBytesSource(Uint8List.fromList([1, 2, 3]), mimeType: 'audio/ogg');
      expect(source.bytes, [1, 2, 3]);
      expect(source.mimeType, 'audio/ogg');
    });

    test('asset source holds asset path', () {
      const source = KoheraAssetSource('assets/audio/ringtone.mp3');
      expect(source.assetPath, 'assets/audio/ringtone.mp3');
    });
  });

  group('MediaPlaybackService', () {
    test('registering a second player pauses the active one', () async {
      final service = MediaPlaybackService();
      final first = _FakeKoheraPlayer();
      final second = _FakeKoheraPlayer();

      service.registerPlayer('event_a', first);
      expect(service.activeEventId, 'event_a');

      service.registerPlayer('event_b', second);
      await Future<void>.delayed(Duration.zero);

      expect(first.pauseCount, 1);
      expect(service.activeEventId, 'event_b');
    });

    test('registering the same player again does not pause it', () async {
      final service = MediaPlaybackService();
      final player = _FakeKoheraPlayer();

      service.registerPlayer('event_a', player);
      service.registerPlayer('event_a', player);

      expect(player.pauseCount, 0);
    });

    test('unregister clears the active player', () {
      final service = MediaPlaybackService();
      final player = _FakeKoheraPlayer();

      service.registerPlayer('event_a', player);
      service.unregisterPlayer('event_a');

      expect(service.activeEventId, isNull);
    });

    test('pauseActive pauses the active player', () async {
      final service = MediaPlaybackService();
      final player = _FakeKoheraPlayer();

      service.registerPlayer('event_a', player);
      service.pauseActive();
      await Future<void>.delayed(Duration.zero);

      expect(player.pauseCount, 1);
    });

    test('unregister of a non-active event is a no-op', () {
      final service = MediaPlaybackService();
      final player = _FakeKoheraPlayer();

      service.registerPlayer('event_a', player);
      service.unregisterPlayer('event_b');

      expect(service.activeEventId, 'event_a');
    });
  });
}

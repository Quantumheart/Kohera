import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/media_player_factory.dart';
import 'package:kohera/core/media/resolved_media.dart';
import 'package:kohera/core/media/video_media_player.dart';

void main() {
  group('ResolvedMedia', () {
    test('holds filePath, bytes, mimeType', () {
      const media = ResolvedMedia(
        filePath: '/tmp/foo.ogg',
        mimeType: 'audio/ogg',
      );
      expect(media.filePath, '/tmp/foo.ogg');
      expect(media.mimeType, 'audio/ogg');
      expect(media.bytes, isNull);
    });

    test('holds bytes for web', () {
      const media = ResolvedMedia(mimeType: 'video/mp4');
      expect(media.filePath, isNull);
      expect(media.mimeType, 'video/mp4');
    });
  });

  group('MediaPlayerFactory', () {
    test('createAudio returns MediaPlayer', () {
      final player = MediaPlayerFactory.createAudio();
      expect(player, isA<MediaPlayer>());
    });

    test('createVideo returns VideoMediaPlayer', () {
      final player = MediaPlayerFactory.createVideo();
      expect(player, isA<VideoMediaPlayer>());
      expect(player, isA<MediaPlayer>());
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';

void main() {
  group('KoheraMediaContent', () {
    test('constructs with all fields', () {
      const media = KoheraMediaContent(
        mediaType: KoheraMediaType.image,
        mxcUrl: 'mxc://example.com/abc',
        mimeType: 'image/png',
        fileSize: 1024,
        width: 800,
        height: 600,
        duration: null,
        fileName: 'photo.png',
        caption: 'photo.png',
        thumbnailUrl: 'mxc://example.com/thumb',
        senderName: 'Alice',
        senderId: '@alice:example.com',
        senderAvatarUrl: 'mxc://example.com/avatar',
        timestamp: null,
      );

      expect(media.mediaType, KoheraMediaType.image);
      expect(media.mxcUrl, 'mxc://example.com/abc');
      expect(media.mimeType, 'image/png');
      expect(media.fileSize, 1024);
      expect(media.width, 800);
      expect(media.height, 600);
      expect(media.fileName, 'photo.png');
      expect(media.thumbnailUrl, 'mxc://example.com/thumb');
      expect(media.senderName, 'Alice');
      expect(media.senderId, '@alice:example.com');
    });

    test('two contents with same mxcUrl are equal', () {
      const a = KoheraMediaContent(
        mediaType: KoheraMediaType.image,
        mxcUrl: 'mxc://example.com/abc',
        fileName: 'photo.png',
      );
      const b = KoheraMediaContent(
        mediaType: KoheraMediaType.video,
        mxcUrl: 'mxc://example.com/abc',
        fileName: 'video.mp4',
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('two contents with different mxcUrl are not equal', () {
      const a = KoheraMediaContent(
        mediaType: KoheraMediaType.image,
        mxcUrl: 'mxc://example.com/abc',
      );
      const b = KoheraMediaContent(
        mediaType: KoheraMediaType.image,
        mxcUrl: 'mxc://example.com/def',
      );

      expect(a, isNot(equals(b)));
    });

    test('copyWith updates only specified fields', () {
      const original = KoheraMediaContent(
        mediaType: KoheraMediaType.image,
        mxcUrl: 'mxc://example.com/abc',
        fileName: 'photo.png',
        fileSize: 1024,
      );

      final updated = original.copyWith(
        mediaType: KoheraMediaType.video,
        fileSize: 2048,
      );

      expect(updated.mediaType, KoheraMediaType.video);
      expect(updated.mxcUrl, 'mxc://example.com/abc');
      expect(updated.fileName, 'photo.png');
      expect(updated.fileSize, 2048);
    });

    test('toString contains key fields', () {
      const media = KoheraMediaContent(
        mediaType: KoheraMediaType.audio,
        mxcUrl: 'mxc://example.com/audio',
        fileName: 'song.mp3',
        fileSize: 5000,
      );

      expect(media.toString(), contains('audio'));
      expect(media.toString(), contains('song.mp3'));
      expect(media.toString(), contains('5000'));
    });
  });

  group('KoheraMediaType', () {
    test('has all expected values', () {
      expect(KoheraMediaType.values, contains(KoheraMediaType.image));
      expect(KoheraMediaType.values, contains(KoheraMediaType.video));
      expect(KoheraMediaType.values, contains(KoheraMediaType.audio));
      expect(KoheraMediaType.values, contains(KoheraMediaType.file));
      expect(KoheraMediaType.values, contains(KoheraMediaType.sticker));
    });
  });
}
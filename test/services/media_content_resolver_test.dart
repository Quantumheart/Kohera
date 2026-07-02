import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/features/chat/services/media_content_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<Room>(),
])
import 'media_content_resolver_test.mocks.dart';

void main() {
  late MockEvent event;
  late MockUser sender;
  late MockRoom room;

  setUp(() {
    event = MockEvent();
    sender = MockUser();
    room = MockRoom();

    when(event.eventId).thenReturn(r'$123:server');
    when(event.senderId).thenReturn('@alice:server');
    when(event.type).thenReturn(EventTypes.Message);
    when(event.originServerTs).thenReturn(DateTime(2026, 1, 15, 10, 30));
    when(event.senderFromMemoryOrFallback).thenReturn(sender);
    when(event.room).thenReturn(room);
    when(event.body).thenReturn('photo.png');
    when(event.content).thenReturn(<String, Object?>{
      'url': 'mxc://server/abc',
      'msgtype': 'm.image',
      'info': {
        'mimetype': 'image/png',
        'size': 1024,
        'w': 800,
        'h': 600,
        'thumbnail_url': 'mxc://server/thumb',
      },
    });
    when(event.messageType).thenReturn(MessageTypes.Image);
    when(event.attachmentMxcUrl).thenReturn(Uri.parse('mxc://server/abc'));
    when(sender.calcDisplayname()).thenReturn('Alice');
    when(sender.avatarUrl).thenReturn(null);
  });

  group('MediaContentResolver', () {
    test('converts image event', () {
      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.image);
      expect(media.mxcUrl, 'mxc://server/abc');
      expect(media.mimeType, 'image/png');
      expect(media.fileSize, 1024);
      expect(media.width, 800);
      expect(media.height, 600);
      expect(media.fileName, 'photo.png');
      expect(media.caption, 'photo.png');
      expect(media.thumbnailUrl, 'mxc://server/thumb');
      expect(media.senderName, 'Alice');
      expect(media.senderId, '@alice:server');
    });

    test('converts video event', () {
      when(event.messageType).thenReturn(MessageTypes.Video);
      when(event.content).thenReturn(<String, Object?>{
        'url': 'mxc://server/video',
        'msgtype': 'm.video',
        'info': {
          'mimetype': 'video/mp4',
          'size': 5242880,
          'duration': 10000,
        },
      });
      when(event.attachmentMxcUrl).thenReturn(Uri.parse('mxc://server/video'));
      when(event.body).thenReturn('video.mp4');

      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.video);
      expect(media.mimeType, 'video/mp4');
      expect(media.fileSize, 5242880);
      expect(media.duration, 10000);
      expect(media.fileName, 'video.mp4');
    });

    test('converts audio event', () {
      when(event.messageType).thenReturn(MessageTypes.Audio);
      when(event.content).thenReturn(<String, Object?>{
        'url': 'mxc://server/audio',
        'msgtype': 'm.audio',
        'info': {
          'mimetype': 'audio/ogg',
          'size': 1048576,
          'duration': 5000,
        },
      });
      when(event.attachmentMxcUrl).thenReturn(Uri.parse('mxc://server/audio'));
      when(event.body).thenReturn('audio.ogg');

      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.audio);
      expect(media.mimeType, 'audio/ogg');
      expect(media.fileSize, 1048576);
      expect(media.duration, 5000);
      expect(media.fileName, 'audio.ogg');
    });

    test('converts file event', () {
      when(event.messageType).thenReturn(MessageTypes.File);
      when(event.content).thenReturn(<String, Object?>{
        'url': 'mxc://server/file',
        'msgtype': 'm.file',
        'info': {
          'mimetype': 'application/pdf',
          'size': 2048000,
        },
      });
      when(event.attachmentMxcUrl).thenReturn(Uri.parse('mxc://server/file'));
      when(event.body).thenReturn('document.pdf');

      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.file);
      expect(media.mimeType, 'application/pdf');
      expect(media.fileSize, 2048000);
      expect(media.fileName, 'document.pdf');
    });

    test('converts sticker event', () {
      when(event.type).thenReturn(EventTypes.Sticker);
      when(event.content).thenReturn(<String, Object?>{
        'url': 'mxc://server/sticker',
        'body': 'sticker',
        'info': {
          'mimetype': 'image/png',
          'w': 256,
          'h': 256,
        },
      });
      when(event.messageType).thenReturn('m.sticker');
      when(event.attachmentMxcUrl).thenReturn(Uri.parse('mxc://server/sticker'));
      when(event.body).thenReturn('sticker');

      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.sticker);
      expect(media.width, 256);
      expect(media.height, 256);
      expect(media.fileName, 'sticker');
    });

    test('extracts sender avatar URL', () {
      when(sender.avatarUrl).thenReturn(Uri.parse('mxc://server/avatar'));

      final media = const MediaContentResolver()(event);

      expect(media.senderAvatarUrl, 'mxc://server/avatar');
    });

    test('falls back to attachmentMxcUrl when content has no url', () {
      when(event.content).thenReturn(<String, Object?>{
        'msgtype': 'm.image',
        'info': {'mimetype': 'image/png'},
      });
      when(event.attachmentMxcUrl).thenReturn(Uri.parse('mxc://server/fallback'));
      when(event.messageType).thenReturn(MessageTypes.Image);

      final media = const MediaContentResolver()(event);

      expect(media.mxcUrl, 'mxc://server/fallback');
    });

    test('handles missing info map gracefully', () {
      when(event.content).thenReturn(<String, Object?>{
        'url': 'mxc://server/abc',
        'msgtype': 'm.image',
      });
      when(event.messageType).thenReturn(MessageTypes.Image);

      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.image);
      expect(media.mimeType, isNull);
      expect(media.fileSize, isNull);
      expect(media.width, isNull);
      expect(media.height, isNull);
      expect(media.duration, isNull);
    });

    test('unknown messageType defaults to file', () {
      when(event.messageType).thenReturn('m.unknown');
      when(event.type).thenReturn('m.room.message');

      final media = const MediaContentResolver()(event);

      expect(media.mediaType, KoheraMediaType.file);
    });
  });
}

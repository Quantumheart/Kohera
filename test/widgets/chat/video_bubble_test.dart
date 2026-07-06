import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/widgets/video_bubble.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';


@GenerateNiceMocks([
  MockSpec<MediaController>(),
  MockSpec<MediaPlaybackService>(),
  MockSpec<AvatarResolver>(),
])
import 'video_bubble_test.mocks.dart';

KoheraMediaContent _makeMedia({
  int? duration,
  int? fileSize,
  String fileName = 'video.mp4',
}) =>
    KoheraMediaContent(
      mediaType: KoheraMediaType.video,
      mxcUrl: 'mxc://server/video',
      mimeType: 'video/mp4',
      fileSize: fileSize ?? 5 * 1024 * 1024,
      duration: duration,
      fileName: fileName,
    );

MockMediaController _makeController({
  String eventId = 'event_1',
  bool isEncrypted = false,
  String? thumbUrl = 'https://example.com/thumb.jpg',
}) {
  final controller = MockMediaController();
  when(controller.eventId).thenReturn(eventId);
  when(controller.isEncrypted).thenReturn(isEncrypted);
  when(controller.isPendingSend).thenReturn(false);
  when(controller.mimeType).thenReturn('video/mp4');
  when(controller.authHeaders(any)).thenReturn(null);
  when(
    controller.getAttachmentUri(
      getThumbnail: anyNamed('getThumbnail'),
      width: anyNamed('width'),
      height: anyNamed('height'),
    ),
  ).thenAnswer(
    (_) async => thumbUrl,
  );
  return controller;
}

Widget _wrap(
  KoheraMediaContent media,
  MediaController controller, {
  bool isMe = true,
  MediaPlaybackService? playbackService,
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: ChangeNotifierProvider<MediaPlaybackService>.value(
        value: playbackService ?? MockMediaPlaybackService(),
        child: VideoBubble(
          media: media,
          controller: controller,
          isMe: isMe,
          avatarResolver: MockAvatarResolver(),
        ),
      ),
    ),
  );
}

void main() {
  group('VideoBubble', () {
    testWidgets('renders thumbnail correctly (unencrypted)', (tester) async {
      final media = _makeMedia(duration: 10000, fileSize: 5 * 1024 * 1024);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);
    });

    testWidgets('renders thumbnail correctly (encrypted)', (tester) async {
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x63,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);
      final media = _makeMedia(duration: 10000);
      final controller = _makeController(
        isEncrypted: true,
        thumbUrl: null,
      );
      when(controller.downloadAndDecrypt(getThumbnail: true))
          .thenAnswer((_) async => pngBytes);

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders file fallback when too large', (tester) async {
      final media = _makeMedia(fileSize: 200 * 1024 * 1024);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));

      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    });

    testWidgets('shows duration label', (tester) async {
      final media = _makeMedia(duration: 10000);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      expect(find.text('00:10'), findsOneWidget);
    });
  });
}

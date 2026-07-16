import 'dart:async';
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
  int? width,
  int? height,
  String fileName = 'video.mp4',
}) =>
    KoheraMediaContent(
      mediaType: KoheraMediaType.video,
      mxcUrl: 'mxc://server/video',
      mimeType: 'video/mp4',
      fileSize: fileSize ?? 5 * 1024 * 1024,
      width: width,
      height: height,
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
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int maxFrames = 30,
  }) async {
    for (var i = 0; i < maxFrames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.any(finder)) return;
    }
    fail('pumpUntil: $finder not found within $maxFrames frames');
  }

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

    testWidgets('shows skeleton while the thumbnail loads', (tester) async {
      final completer = Completer<String?>();
      final media = _makeMedia(duration: 10000);
      final controller = _makeController();
      when(
        controller.getAttachmentUri(
          getThumbnail: anyNamed('getThumbnail'),
          width: anyNamed('width'),
          height: anyNamed('height'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      expect(find.byKey(const ValueKey('videoSkeleton')), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      completer.complete('https://example.com/thumb.jpg');
      await pumpUntil(tester, find.byIcon(Icons.play_arrow_rounded));

      expect(find.byKey(const ValueKey('videoSkeleton')), findsNothing);
    });

    testWidgets('failed thumbnail keeps play button and offers retry that refetches',
        (tester) async {
      var fail = true;
      final media = _makeMedia(duration: 10000);
      final controller = _makeController();
      when(
        controller.getAttachmentUri(
          getThumbnail: anyNamed('getThumbnail'),
          width: anyNamed('width'),
          height: anyNamed('height'),
        ),
      ).thenAnswer((_) async {
        if (fail) throw Exception('uri boom');
        return 'https://example.com/thumb.jpg';
      });

      await tester.pumpWidget(_wrap(media, controller));
      await pumpUntil(tester, find.byIcon(Icons.refresh_rounded));

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      fail = false;
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await pumpUntil(tester, find.byIcon(Icons.play_arrow_rounded));

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('retry re-runs init synchronously and ignores repeat taps',
        (tester) async {
      var fullMediaCalls = 0;
      final hang = Completer<Uint8List>();
      final media = _makeMedia(duration: 10000);
      final controller = _makeController();
      when(
        controller.downloadAndDecrypt(getThumbnail: anyNamed('getThumbnail')),
      ).thenAnswer((_) {
        fullMediaCalls++;
        if (fullMediaCalls == 1) {
          return Future<Uint8List>.error(Exception('media fetch failed'));
        }
        return hang.future;
      });

      await tester.pumpWidget(_wrap(media, controller));
      await pumpUntil(tester, find.byIcon(Icons.play_arrow_rounded));
      expect(fullMediaCalls, 0);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await pumpUntil(tester, find.byIcon(Icons.error_outline_rounded));
      expect(fullMediaCalls, 1);

      await tester.tap(find.byIcon(Icons.error_outline_rounded));
      expect(fullMediaCalls, 2);

      final center = tester.getCenter(find.byType(VideoBubble));
      await tester.tapAt(center);
      expect(fullMediaCalls, 2);
    });

    testWidgets('portrait video renders a portrait aspect box',
        (tester) async {
      final media = _makeMedia(width: 1080, height: 1920, duration: 10000);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      final box = tester.getSize(
        find.descendant(
          of: find.byType(VideoBubble),
          matching: find.byType(Stack),
        ),
      );
      expect(box.width, closeTo(260 * (1080 / 1920), 0.01));
      expect(box.height, closeTo(260, 0.01));
    });

    testWidgets('landscape video renders a landscape aspect box',
        (tester) async {
      final media = _makeMedia(width: 1920, height: 1080, duration: 10000);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      final box = tester.getSize(
        find.descendant(
          of: find.byType(VideoBubble),
          matching: find.byType(Stack),
        ),
      );
      expect(box.width, closeTo(280, 0.01));
      expect(box.height, closeTo(280 / (1920 / 1080), 0.01));
    });

    testWidgets('missing dimensions fall back to default 16:9 box',
        (tester) async {
      final media = _makeMedia(duration: 10000);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      final box = tester.getSize(
        find.descendant(
          of: find.byType(VideoBubble),
          matching: find.byType(Stack),
        ),
      );
      expect(box.width, closeTo(280, 0.01));
      expect(box.height, closeTo(280 / (16 / 9), 0.01));
    });

    testWidgets('box never exceeds max bubble bounds', (tester) async {
      final media = _makeMedia(width: 1080, height: 1920, duration: 10000);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));
      await tester.pump();

      final box = tester.getSize(
        find.descendant(
          of: find.byType(VideoBubble),
          matching: find.byType(Stack),
        ),
      );
      expect(box.width, lessThanOrEqualTo(280));
      expect(box.height, lessThanOrEqualTo(260));
    });
  });
}

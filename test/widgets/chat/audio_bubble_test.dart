import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/features/chat/services/media_controller.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/widgets/audio_bubble.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<MediaController>(), MockSpec<MediaPlaybackService>()])
import 'audio_bubble_test.mocks.dart';

KoheraMediaContent _makeMedia({
  int? duration,
  int? fileSize,
  String fileName = 'audio.mp3',
}) =>
    KoheraMediaContent(
      mediaType: KoheraMediaType.audio,
      mxcUrl: 'mxc://server/audio',
      mimeType: 'audio/mpeg',
      fileSize: fileSize ?? 1024 * 1024,
      duration: duration,
      fileName: fileName,
    );

MockMediaController _makeController({
  String eventId = 'event_1',
  bool isPendingSend = false,
}) {
  final controller = MockMediaController();
  when(controller.eventId).thenReturn(eventId);
  when(controller.isPendingSend).thenReturn(isPendingSend);
  when(controller.isEncrypted).thenReturn(false);
  when(controller.mimeType).thenReturn('audio/mpeg');
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
        child: AudioBubble(
          media: media,
          controller: controller,
          isMe: isMe,
        ),
      ),
    ),
  );
}

void main() {
  group('AudioBubble', () {
    testWidgets('renders correctly in initial state', (tester) async {
      final media = _makeMedia(duration: 5000, fileSize: 1048576);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('00:05'), findsOneWidget);
      expect(find.byType(CustomPaint), findsAtLeast(1));
    });

    testWidgets('renders file fallback when too large', (tester) async {
      final media = _makeMedia(fileSize: 200 * 1024 * 1024);
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));

      expect(find.byIcon(Icons.audiotrack_rounded), findsOneWidget);
    });

    testWidgets('disables play button when pending send', (tester) async {
      final media = _makeMedia(duration: 5000);
      final controller = _makeController(isPendingSend: true);

      await tester.pumpWidget(_wrap(media, controller));

      final icon = tester.widget<IconButton>(find.byType(IconButton).first);
      expect(icon.onPressed, isNull);
    });

    testWidgets('shows file name and size in fallback', (tester) async {
      final media = _makeMedia(fileSize: 200 * 1024 * 1024, fileName: 'song.mp3');
      final controller = _makeController();

      await tester.pumpWidget(_wrap(media, controller));

      expect(find.text('song.mp3'), findsOneWidget);
    });
  });
}

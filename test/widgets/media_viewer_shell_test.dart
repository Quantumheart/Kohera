import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_media_type.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<MediaController>(),
  MockSpec<AvatarResolver>(),
])
import 'media_viewer_shell_test.mocks.dart';

KoheraMediaContent _makeMedia({
  String senderName = 'Alice',
  String senderId = '@alice:example.com',
  String fileName = 'image.png',
}) =>
    KoheraMediaContent(
      mediaType: KoheraMediaType.image,
      mxcUrl: 'mxc://server/image',
      fileName: fileName,
      senderName: senderName,
      senderId: senderId,
      timestamp: DateTime(2026),
    );

MockMediaController _makeController() {
  final controller = MockMediaController();
  when(controller.eventId).thenReturn(r'$123:server');
  when(controller.isEncrypted).thenReturn(false);
  return controller;
}

Widget buildTestWidget({
  KoheraMediaContent? media,
  MediaController? controller,
  Widget? child,
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: MediaViewerShell(
        media: media ?? _makeMedia(),
        controller: controller ?? _makeController(),
        avatarResolver: MockAvatarResolver(),
        child: child ?? const Placeholder(),
      ),
    ),
  );
}

void main() {
  group('MediaViewerShell', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Text('media content')),
      );
      await tester.pump();

      expect(find.text('media content'), findsOneWidget);
    });

    testWidgets('shows sender name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('download button is present', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    });

    testWidgets('close button is present', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    Future<void> openViewer(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    body: MediaViewerShell(
                      media: _makeMedia(),
                      controller: _makeController(),
                      avatarResolver: MockAvatarResolver(),
                      child: const Placeholder(),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('swipe down dismisses the viewer', (tester) async {
      await openViewer(tester);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.timedDrag(
        find.byType(MediaViewerShell),
        const Offset(0, 200),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('small drag snaps back without dismissing', (tester) async {
      await openViewer(tester);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.timedDrag(
        find.byType(MediaViewerShell),
        const Offset(0, 60),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('open'), findsNothing);
    });
  });
}

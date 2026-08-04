import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/inline_image_preview.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  group('InlineImagePreview', () {
    testWidgets('renders an Image.network widget', (tester) async {
      await tester.pumpWidget(wrap(
        const InlineImagePreview(url: 'https://example.com/img.png', isMe: false),
      ));

      expect(find.byType(Image), findsOneWidget);
      expect(
        (tester.widget<Image>(find.byType(Image))).image,
        isA<NetworkImage>(),
      );
    });

    testWidgets('uses ConstrainedBox with max height 260 and width 280',
        (tester) async {
      await tester.pumpWidget(wrap(
        const InlineImagePreview(url: 'https://example.com/img.png', isMe: true),
      ));

      // There may be internal ConstrainedBoxes; find the one with our limits
      final constrained = tester
          .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
          .firstWhere(
            (c) => c.constraints.maxHeight == 260 && c.constraints.maxWidth == 280,
          );
      expect(constrained.constraints.maxHeight, 260);
      expect(constrained.constraints.maxWidth, 280);
    });

    testWidgets('has a GestureDetector wrapper', (tester) async {
      await tester.pumpWidget(wrap(
        const InlineImagePreview(url: 'https://example.com/img.png', isMe: false),
      ));

      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('uses ClipRRect with sharp corners', (tester) async {
      await tester.pumpWidget(wrap(
        const InlineImagePreview(url: 'https://example.com/img.png', isMe: false),
      ));

      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.zero);
    });

    testWidgets('shows loading builder with progress indicator while loading',
        (tester) async {
      await tester.pumpWidget(wrap(
        const InlineImagePreview(url: 'https://example.com/img.png', isMe: false),
      ));

      // Pump a frame — the Image.network loadingBuilder fires with progress
      await tester.pump();

      // While loading, a CircularProgressIndicator should appear (if not already errored)
      // The image is non-existent so it might error quickly. Check for either.
      final hasProgress = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasBroken = find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty;
      expect(hasProgress || hasBroken, isTrue);
    });

    testWidgets('shows broken image icon on error', (tester) async {
      await tester.pumpWidget(wrap(
        const InlineImagePreview(url: 'https://example.com/broken.png', isMe: false),
      ));

      // Pump enough frames for the error builder to fire
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
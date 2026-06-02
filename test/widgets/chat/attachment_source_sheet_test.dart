import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/attachment_source_sheet.dart';

void main() {
  Future<AttachmentSource?> openSheet(
    WidgetTester tester, {
    bool showGif = false,
    bool showSticker = false,
  }) async {
    AttachmentSource? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showAttachmentSourceSheet(
                context,
                showGif: showGif,
                showSticker: showSticker,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('hides GIF and sticker options by default', (tester) async {
    await openSheet(tester);

    expect(find.text('Photo or Video'), findsOneWidget);
    expect(find.text('GIF'), findsNothing);
    expect(find.text('Stickers & Emoji'), findsNothing);
  });

  testWidgets('shows GIF and sticker options when enabled', (tester) async {
    await openSheet(tester, showGif: true, showSticker: true);

    expect(find.text('GIF'), findsOneWidget);
    expect(find.text('Stickers & Emoji'), findsOneWidget);
  });

  testWidgets('returns gif source when GIF option tapped', (tester) async {
    AttachmentSource? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showAttachmentSourceSheet(context, showGif: true);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF'));
    await tester.pumpAndSettle();

    expect(result, AttachmentSource.gif);
  });
}

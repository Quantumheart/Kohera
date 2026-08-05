// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/sticker_message_item.dart';

KoheraMessageDisplay _msg({String eventId = '\$sticker:example.com'}) {
  return KoheraMessageDisplay(
    eventId: eventId,
    senderId: '@alice:example.com',
    senderName: 'Alice',
    body: 'A sticker',
    messageType: 'm.sticker',
    eventType: 'm.sticker',
    timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
    status: KoheraMessageStatus.sent,
    content: {},
  );
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('StickerMessageItem', () {
    testWidgets('renders the sticker widget', (tester) async {
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(key: Key('sticker'), width: 80, height: 80),
          isMe: false,
          isMobile: true,
          onToggleReaction: (_, __) async {},
        ),
      ));

      expect(find.byKey(const Key('sticker')), findsOneWidget);
    });

    testWidgets('renders reaction widget when provided', (tester) async {
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(width: 80, height: 80),
          isMe: false,
          isMobile: true,
          onToggleReaction: (_, __) async {},
          reactionWidget: const Text('👍 2'),
        ),
      ));

      expect(find.text('👍 2'), findsOneWidget);
    });

    testWidgets('does not render reaction widget when null', (tester) async {
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(width: 80, height: 80),
          isMe: false,
          isMobile: true,
          onToggleReaction: (_, __) async {},
        ),
      ));

      expect(find.text('👍 2'), findsNothing);
    });

    testWidgets('calls onShowMobileActions via LongPressWrapper on touch platforms',
        (tester) async {
      // LongPressWrapper is only rendered when isTouchDevice is true.
      // On the Linux test runner isTouchDevice is false, so the desktop
      // Listener path is used instead. We skip this on non-touch runners.
      if (!isTouchDevice) {
        debugPrint('Skipped: requires a touch platform (isTouchDevice=true)');
        return;
      }
      var longPressCalled = false;
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(width: 80, height: 80),
          isMe: false,
          isMobile: true,
          onToggleReaction: (_, __) async {},
          onShowMobileActions: (rect) => longPressCalled = true,
        ),
      ));

      await tester.longPress(find.byType(StickerMessageItem));
      await tester.pumpAndSettle();

      expect(longPressCalled, isTrue);
    });

    testWidgets('uses MouseRegion and Listener on desktop (non-touch)',
        (tester) async {
      // On the Linux test runner, isTouchDevice is false so the desktop
      // path renders MouseRegion + Listener.
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(width: 80, height: 80),
          isMe: false,
          isMobile: false,
          onToggleReaction: (_, __) async {},
          onOpenContextMenu: (_) {},
        ),
      ));

      expect(find.byType(MouseRegion), findsWidgets);
      expect(find.byType(Listener), findsWidgets);
    });

    testWidgets('aligns to end when isMe is true', (tester) async {
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(width: 80, height: 80),
          isMe: true,
          isMobile: true,
          onToggleReaction: (_, __) async {},
        ),
      ));

      final column = tester.widget<Column>(find.byType(Column).first);
      expect(column.crossAxisAlignment, CrossAxisAlignment.end);
    });

    testWidgets('aligns to start when isMe is false', (tester) async {
      await tester.pumpWidget(wrap(
        StickerMessageItem(
          message: _msg(),
          stickerWidget: const SizedBox(width: 80, height: 80),
          isMe: false,
          isMobile: true,
          onToggleReaction: (_, __) async {},
        ),
      ));

      final column = tester.widget<Column>(find.byType(Column).first);
      expect(column.crossAxisAlignment, CrossAxisAlignment.start);
    });
  });
}

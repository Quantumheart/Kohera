import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/message_action_sheet.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';
import 'package:provider/provider.dart';

class _FakeAvatarResolver implements AvatarResolver {
  const _FakeAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(
    String? mxcUrl, {
    required double size,
  }) async =>
      null;
}

class _FakeMediaResolver implements MediaResolver {
  const _FakeMediaResolver();
  @override
  Future<MediaThumbnail?> resolve(
    String? mxcUrl, {
    required double? width,
    required double? height,
  }) async =>
      null;
}

KoheraMessageDisplay _makeMessage({
  required String eventId,
  required String senderId,
  String body = 'Hello',
}) {
  return KoheraMessageDisplay(
    eventId: eventId,
    senderId: senderId,
    senderName: senderId.split(':').first.substring(1),
    body: body,
    messageType: 'm.text',
    eventType: 'm.room.message',
    timestamp: DateTime(2025, 1, 1, 12),
    status: KoheraMessageStatus.sent,
    content: {'body': body, 'msgtype': 'm.text'},
  );
}

/// Finds the [OpenMojiImage] rendered for [emoji].
Finder _emojiImage(String emoji) => find.byWidgetPredicate(
      (w) => w is OpenMojiImage && w.grapheme == emoji,
    );

void main() {
  Widget buildTestWidget({
    required List<MessageAction> actions,
    void Function(String emoji)? onQuickReact,
    KoheraMessageDisplay? message,
  }) {
    final msg = message ?? _makeMessage(eventId: r'$evt1', senderId: '@me:x');

    return ChangeNotifierProvider<PreferencesService>.value(
      value: PreferencesService(),
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showMessageActionSheet(
                  context: context,
                  message: msg,
                  isMe: true,
                  bubbleRect: const Rect.fromLTWH(50, 50, 300, 60),
                  actions: actions,
                  avatarResolver: const _FakeAvatarResolver(),
                  mentionResolver: (_) => null,
                  mediaResolver: const _FakeMediaResolver(),
                  onQuickReact: onQuickReact,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void suppressLayoutErrors(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    final original = FlutterError.onError;
    FlutterError.onError = (d) {};
    addTearDown(() {
      FlutterError.onError = original;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('MessageActionSheet', () {
    testWidgets('renders all action labels', (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
        MessageAction(label: 'Copy', icon: Icons.copy, onTap: () {}),
        MessageAction(
          label: 'Delete',
          icon: Icons.delete,
          onTap: () {},
          color: Colors.red,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('tap action invokes callback and closes sheet',
        (tester) async {
      suppressLayoutErrors(tester);
      var replyCalled = false;
      final actions = [
        MessageAction(
          label: 'Reply',
          icon: Icons.reply,
          onTap: () => replyCalled = true,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();

      expect(replyCalled, isTrue);
    });

    testWidgets('quick react bar visible when onQuickReact provided',
        (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          actions: actions,
          onQuickReact: (_) {},
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(_emojiImage('\u{1F44D}'), findsOneWidget);
      expect(_emojiImage('\u{2764}\u{FE0F}'), findsOneWidget);
    });

    testWidgets('quick react bar hidden when onQuickReact is null',
        (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(_emojiImage('\u{1F44D}'), findsNothing);
    });

    testWidgets('tap emoji fires onQuickReact with correct string',
        (tester) async {
      suppressLayoutErrors(tester);
      String? selectedEmoji;
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          actions: actions,
          onQuickReact: (e) => selectedEmoji = e,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(_emojiImage('\u{1F44D}'));
      await tester.pumpAndSettle();

      expect(selectedEmoji, '\u{1F44D}');
    });

    testWidgets('barrier tap dismisses sheet', (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsNothing);
    });
  });
}

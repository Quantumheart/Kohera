import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/core/theme/theme_presets.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/message_bubble.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:provider/provider.dart';

void main() {
  const pico8 = 'pico8';

  Widget buildBubbleScene(ThemeData theme) {
    final prefs = PreferencesService();
    return ChangeNotifierProvider<PreferencesService>.value(
      value: prefs,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: MessageBubble(
            message: KoheraMessageDisplay(
              eventId: r'$test:example.com',
              senderId: '@alice:example.com',
              senderName: 'Alice',
              body: 'Hello, world!',
              messageType: 'm.text',
              eventType: 'm.room.message',
              timestamp: DateTime(2024),
              status: KoheraMessageStatus.sent,
              content: const {},
            ),
            isMe: false,
            isFirst: true,
            avatarResolver: _DummyAvatarResolver(),
            htmlBuilder: (html, style) => Text(html, style: style),
          ),
        ),
      ),
    );
  }

  group('MessageBubble Golden Tests', () {
    testWidgets('message bubble with PICO-8 theme (light)', (tester) async {
      await tester.pumpWidget(
        buildBubbleScene(KoheraTheme.light(preset: getPreset(pico8))),
      );

      await expectLater(
        find.byType(MessageBubble),
        matchesGoldenFile('goldens/message_bubble_pico8_light.png'),
      );
    });

    testWidgets('message bubble with PICO-8 theme (dark)', (tester) async {
      await tester.pumpWidget(
        buildBubbleScene(KoheraTheme.dark(preset: getPreset(pico8))),
      );

      await expectLater(
        find.byType(MessageBubble),
        matchesGoldenFile('goldens/message_bubble_pico8_dark.png'),
      );
    });
  });
}

class _DummyAvatarResolver implements AvatarResolver {
  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size}) {
    return Future.value();
  }
}

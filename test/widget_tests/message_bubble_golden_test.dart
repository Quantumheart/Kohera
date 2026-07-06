import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/message_bubble.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:provider/provider.dart';

void main() {
  group('MessageBubble Golden Tests', () {
    testWidgets('message bubble with PICO-8 theme', (tester) async {
      final prefs = PreferencesService();

      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesService>.value(
          value: prefs,
          child: MaterialApp(
            theme: KoheraTheme.light(),
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
        ),
      );

      await expectLater(
        find.byType(MessageBubble),
        matchesGoldenFile('goldens/message_bubble_pico8.png'),
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:kohera/features/chat/widgets/irc_message_tile.dart';

KoheraMessageDisplay _msg({
  String body = 'Hello, world!',
  String senderName = 'Alice',
  String senderId = '@alice:example.com',
  String messageType = 'm.text',
  bool isEdited = false,
  bool isRedacted = false,
  String? replyEventId,
}) {
  return KoheraMessageDisplay(
    eventId: r'$ev:example.com',
    senderId: senderId,
    senderName: senderName,
    body: body,
    messageType: messageType,
    eventType: 'm.room.message',
    timestamp: DateTime(2024, 1, 2, 14, 32),
    status: KoheraMessageStatus.sent,
    content: const {},
    isEdited: isEdited,
    isRedacted: isRedacted,
    replyEventId: replyEventId,
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: KoheraTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('IrcMessageTile', () {
    testWidgets('renders HH:MM <nick> body for a normal message',
        (tester) async {
      await tester.pumpWidget(_wrap(IrcMessageTile(
        message: _msg(),
        reactions: null,
        media: null,
        isMe: false,
        isFirst: true,
        isMobile: false,
        isPinned: false,
        canPin: false,
        canRedact: false,
        hasThread: false,
        threadReplyCount: 0,
        threadUnreadCount: 0,
        inThread: false,
        highlightedEventId: null,
        avatarResolver: null,
        mediaController: null,
        mentionResolver: null,
        onToggleReaction: null,
      )));

      final text = find.byType(Text).evaluate().map((e) {
        final rich = (e.widget as Text).textSpan;
        return rich?.toPlainText() ?? (e.widget as Text).data ?? '';
      }).join();
      expect(text, contains('14:32'));
      expect(text, contains('<Alice>'));
      expect(text, contains('Hello, world!'));
      // Regression: text messages must not be misrendered as file media.
      expect(text, isNot(contains('[file')));
    });

    testWidgets('uses > marker for own messages', (tester) async {
      await tester.pumpWidget(_wrap(IrcMessageTile(
        message: _msg(senderName: 'Bob', senderId: '@bob:example.com'),
        reactions: null,
        media: null,
        isMe: true,
        isFirst: true,
        isMobile: false,
        isPinned: false,
        canPin: false,
        canRedact: false,
        hasThread: false,
        threadReplyCount: 0,
        threadUnreadCount: 0,
        inThread: false,
        highlightedEventId: null,
        avatarResolver: null,
        mediaController: null,
        mentionResolver: null,
        onToggleReaction: null,
      )));

      final text = find.byType(Text).evaluate().map((e) {
        final rich = (e.widget as Text).textSpan;
        return rich?.toPlainText() ?? (e.widget as Text).data ?? '';
      }).join();
      expect(text, contains('>Bob<'));
    });

    testWidgets('renders emote as * nick action', (tester) async {
      await tester.pumpWidget(_wrap(IrcMessageTile(
        message: _msg(body: 'waves', messageType: 'm.emote'),
        reactions: null,
        media: null,
        isMe: false,
        isFirst: true,
        isMobile: false,
        isPinned: false,
        canPin: false,
        canRedact: false,
        hasThread: false,
        threadReplyCount: 0,
        threadUnreadCount: 0,
        inThread: false,
        highlightedEventId: null,
        avatarResolver: null,
        mediaController: null,
        mentionResolver: null,
        onToggleReaction: null,
      )));

      final text = find.byType(Text).evaluate().map((e) {
        final rich = (e.widget as Text).textSpan;
        return rich?.toPlainText() ?? (e.widget as Text).data ?? '';
      }).join();
      expect(text, contains('* Alice waves'));
      expect(text, isNot(contains('<Alice>')));
    });

    testWidgets('appends (edited) marker', (tester) async {
      await tester.pumpWidget(_wrap(IrcMessageTile(
        message: _msg(body: 'fixed', isEdited: true),
        reactions: null,
        media: null,
        isMe: false,
        isFirst: true,
        isMobile: false,
        isPinned: false,
        canPin: false,
        canRedact: false,
        hasThread: false,
        threadReplyCount: 0,
        threadUnreadCount: 0,
        inThread: false,
        highlightedEventId: null,
        avatarResolver: null,
        mediaController: null,
        mentionResolver: null,
        onToggleReaction: null,
      )));

      final text = find.byType(Text).evaluate().map((e) {
        final rich = (e.widget as Text).textSpan;
        return rich?.toPlainText() ?? (e.widget as Text).data ?? '';
      }).join();
      expect(text, contains('(edited)'));
    });

    testWidgets('renders redacted marker', (tester) async {
      await tester.pumpWidget(_wrap(IrcMessageTile(
        message: _msg(isRedacted: true),
        reactions: null,
        media: null,
        isMe: false,
        isFirst: true,
        isMobile: false,
        isPinned: false,
        canPin: false,
        canRedact: false,
        hasThread: false,
        threadReplyCount: 0,
        threadUnreadCount: 0,
        inThread: false,
        highlightedEventId: null,
        avatarResolver: null,
        mediaController: null,
        mentionResolver: null,
        onToggleReaction: null,
      )));

      final text = find.byType(Text).evaluate().map((e) {
        final rich = (e.widget as Text).textSpan;
        return rich?.toPlainText() ?? (e.widget as Text).data ?? '';
      }).join();
      expect(text, contains('redacted'));
    });

    testWidgets('renders poll as [poll] label with question', (tester) async {
      final poll = KoheraPoll(
        question: 'Tea or coffee?',
        answers: const [
          KoheraPollAnswer(id: 'a1', label: 'Yes'),
          KoheraPollAnswer(id: 'a2', label: 'No'),
        ],
        kind: KoheraPollKind.undisclosed,
        maxSelections: 1,
        ended: false,
        responseCount: 0,
        tallies: const {'a1': 0, 'a2': 0},
      );

      await tester.pumpWidget(_wrap(IrcMessageTile(
        message: _msg(body: ''),
        reactions: null,
        media: null,
        poll: poll,
        isMe: false,
        isFirst: true,
        isMobile: false,
        isPinned: false,
        canPin: false,
        canRedact: false,
        hasThread: false,
        threadReplyCount: 0,
        threadUnreadCount: 0,
        inThread: false,
        highlightedEventId: null,
        avatarResolver: null,
        mediaController: null,
        mentionResolver: null,
        onToggleReaction: null,
      )));

      final text = find.byType(Text).evaluate().map((e) {
        final rich = (e.widget as Text).textSpan;
        return rich?.toPlainText() ?? (e.widget as Text).data ?? '';
      }).join();
      expect(text, contains('[poll: open]'));
      expect(text, contains('Tea or coffee?'));
    });
  });
}

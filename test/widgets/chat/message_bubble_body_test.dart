import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/verification_request_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';

@GenerateNiceMocks([MockSpec<Room>()])
import 'message_bubble_body_test.mocks.dart';

late MockRoom _mockRoom;

KoheraMessageDisplay _makeMessage({
  String msgtype = 'm.text',
  String body = 'hello',
  String senderId = '@alice:example.com',
  String senderName = 'Alice',
  bool redacted = false,
  String? formattedHtml,
  String? redactorId,
  String? redactorName,
}) {
  return KoheraMessageDisplay(
    eventId: r'$test:example.com',
    senderId: senderId,
    senderName: senderName,
    body: body,
    formattedHtml: formattedHtml,
    messageType: msgtype,
    eventType: 'm.room.message',
    timestamp: DateTime(2026, 1, 15, 14, 30),
    isRedacted: redacted,
    redactorId: redactorId,
    redactorName: redactorName,
    status: KoheraMessageStatus.sent,
    content: <String, Object?>{
      'body': body,
      'msgtype': msgtype,
    },
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

Widget _buildBody(
  KoheraMessageDisplay message, {
  bool isMe = false,
}) {
  return _wrap(
    MessageBubbleBody(
      message: message,
      isMe: isMe,
      metrics: DensityMetrics.of(MessageDensity.defaultDensity),
      htmlBuilder: (html, style) => HtmlMessageText(
        html: html,
        style: style,
        isMe: isMe,
        room: _mockRoom,
      ),
    ),
  );
}

void main() {
  setUp(() {
    _mockRoom = MockRoom();
  });

  group('MessageBubbleBody — text dispatch', () {
    testWidgets('plain text renders LinkableText with body', (tester) async {
      final message = _makeMessage(body: 'hello world');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('notice renders as LinkableText', (tester) async {
      final message = _makeMessage(msgtype: 'm.notice', body: 'notice');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byType(LinkableText), findsOneWidget);
    });
  });

  group('MessageBubbleBody — emote', () {
    testWidgets('emote prefixes "* Sender " before body', (tester) async {
      final message = _makeMessage(msgtype: 'm.emote', body: 'waves');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.text('* Alice waves'), findsOneWidget);
    });

    testWidgets('emote with HTML uses HtmlMessageText and escapes sender name',
        (tester) async {
      final message = _makeMessage(
        msgtype: 'm.emote',
        body: 'waves',
        senderName: '<script>evil</script>',
        formattedHtml: '<em>waves</em>',
      );
      await tester.pumpWidget(_buildBody(message));

      expect(find.byType(HtmlMessageText), findsOneWidget);
      final html = tester.widget<HtmlMessageText>(find.byType(HtmlMessageText));
      expect(html.html, contains('&lt;script&gt;evil&lt;/script&gt;'));
      expect(html.html, isNot(contains('<script>evil</script>')));
    });
  });

  group('MessageBubbleBody — server notice', () {
    testWidgets('wraps content with campaign icon', (tester) async {
      final message = _makeMessage(msgtype: 'm.server_notice', body: 'notice');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
      expect(find.text('notice'), findsOneWidget);
    });
  });

  group('MessageBubbleBody — redacted', () {
    testWidgets('isMe shows "You deleted this message"', (tester) async {
      final message = _makeMessage(redacted: true);
      await tester.pumpWidget(_buildBody(message, isMe: true));

      expect(find.text('You deleted this message'), findsOneWidget);
    });

    testWidgets('other sender shows "This message was deleted"',
        (tester) async {
      final message = _makeMessage(redacted: true);
      await tester.pumpWidget(_buildBody(message));

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('moderator redact shows "Deleted by <name>"', (tester) async {
      final message = _makeMessage(
        redacted: true,
        senderId: '@alice:x',
        redactorId: '@bob:x',
        redactorName: 'Bob',
      );
      await tester.pumpWidget(_buildBody(message));

      expect(find.text('Deleted by Bob'), findsOneWidget);
    });

    testWidgets('self-redact shows generic message', (tester) async {
      final message = _makeMessage(
        redacted: true,
        senderId: '@alice:x',
        redactorId: '@alice:x',
      );
      await tester.pumpWidget(_buildBody(message));

      expect(find.text('This message was deleted'), findsOneWidget);
    });
  });

  group('MessageBubbleBody — bad encrypted', () {
    testWidgets('shows lock icon and fallback text', (tester) async {
      final message = _makeMessage(msgtype: 'm.bad.encrypted');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Unable to decrypt this message'), findsOneWidget);
    });
  });

  group('MessageBubbleBody — verification request', () {
    testWidgets('renders VerificationRequestTile', (tester) async {
      final message = _makeMessage(msgtype: 'm.key.verification.request');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byType(VerificationRequestTile), findsOneWidget);
    });
  });

  group('MessageBubbleBody — html body', () {
    testWidgets('non-emote html renders HtmlMessageText without prefix',
        (tester) async {
      final message = _makeMessage(formattedHtml: '<b>hello</b>');
      await tester.pumpWidget(_buildBody(message));

      expect(find.byType(HtmlMessageText), findsOneWidget);
      final html = tester.widget<HtmlMessageText>(find.byType(HtmlMessageText));
      expect(html.html, '<b>hello</b>');
    });
  });
}

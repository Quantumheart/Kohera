import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/call_event_tile.dart';
KoheraMessageDisplay _makeMessage({
  required String eventType,
  String senderName = 'Alice',
  Map<String, Object?> content = const {},
}) {
  return KoheraMessageDisplay(
    eventId: r'$call:example.com',
    senderId: '@alice:example.com',
    senderName: senderName,
    body: '',
    messageType: eventType,
    eventType: eventType,
    timestamp: DateTime(2026, 1, 15, 14, 30),
    status: KoheraMessageStatus.sent,
    content: content,
  );
}

Widget buildWidget(
  KoheraMessageDisplay message, {
  Duration? duration,
  bool isMe = false,
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: Center(
        child: CallEventTile(
          message: message,
          isMe: isMe,
          duration: duration,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders legacy invite as missed-call marker', (tester) async {
    final message = _makeMessage(eventType: 'm.call.invite');
    await tester.pumpWidget(buildWidget(message));

    expect(
      find.text('Missed call from Alice — legacy client'),
      findsOneWidget,
    );
    expect(find.byIcon(KIcons.callMissedRounded), findsWidgets);
  });

  testWidgets('renders call hangup', (tester) async {
    final message = _makeMessage(eventType: 'm.call.hangup');
    await tester.pumpWidget(buildWidget(message));

    expect(find.text('Call ended'), findsOneWidget);
    expect(find.byIcon(KIcons.callEndRounded), findsOneWidget);
  });

  testWidgets('renders missed call', (tester) async {
    final message = _makeMessage(
      eventType: 'm.call.hangup',
      content: {'reason': 'invite_timeout'},
    );
    await tester.pumpWidget(buildWidget(message));

    expect(find.text('Missed call from Alice'), findsOneWidget);
    expect(find.byIcon(KIcons.callMissedRounded), findsOneWidget);
  });

  testWidgets('renders call duration when provided', (tester) async {
    final message = _makeMessage(eventType: 'm.call.hangup');
    await tester.pumpWidget(
      buildWidget(
        message,
        duration: const Duration(minutes: 5, seconds: 32),
      ),
    );

    expect(find.text('Call ended \u2014 5:32'), findsOneWidget);
    expect(find.byIcon(KIcons.callEndRounded), findsOneWidget);
  });

  testWidgets('renders call hangup without duration when null', (tester) async {
    final message = _makeMessage(eventType: 'm.call.hangup');
    await tester.pumpWidget(buildWidget(message));

    expect(find.text('Call ended'), findsOneWidget);
  });

  testWidgets('renders hour-long call duration', (tester) async {
    final message = _makeMessage(eventType: 'm.call.hangup');
    await tester.pumpWidget(
      buildWidget(
        message,
        duration: const Duration(hours: 1, minutes: 2, seconds: 3),
      ),
    );

    expect(find.text('Call ended \u2014 1:02:03'), findsOneWidget);
  });

  testWidgets('renders call reject', (tester) async {
    final message = _makeMessage(eventType: 'm.call.reject');
    await tester.pumpWidget(buildWidget(message));

    expect(find.text('Alice declined the call'), findsOneWidget);
    expect(find.byIcon(KIcons.callEndRounded), findsOneWidget);
  });
}

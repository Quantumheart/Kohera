import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/outbox_action_sheet.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'outbox_action_sheet_test.mocks.dart';

@GenerateNiceMocks([MockSpec<Event>()])
void main() {
  testWidgets('Retry tile invokes sendAgain', (tester) async {
    final event = MockEvent();
    when(event.sendAgain()).thenAnswer((_) async => 'eventId');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OutboxActionSheet(event: event))),
    );
    await tester.tap(find.text('Retry sending'));
    await tester.pumpAndSettle();
    verify(event.sendAgain()).called(1);
  });

  testWidgets('Discard tile invokes cancelSend', (tester) async {
    final event = MockEvent();
    when(event.cancelSend()).thenAnswer((_) async {});
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OutboxActionSheet(event: event))),
    );
    await tester.tap(find.text('Discard message'));
    await tester.pumpAndSettle();
    verify(event.cancelSend()).called(1);
  });
}

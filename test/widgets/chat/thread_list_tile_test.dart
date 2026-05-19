import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/features/chat/widgets/thread_list_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<User>()])
import 'thread_list_tile_test.mocks.dart';

MockEvent _event({
  required String id,
  required String body,
  required int ts,
  String displayName = 'Alice',
  bool redacted = false,
}) {
  final e = MockEvent();
  when(e.eventId).thenReturn(id);
  when(e.body).thenReturn(body);
  when(e.redacted).thenReturn(redacted);
  when(e.originServerTs).thenReturn(DateTime.fromMillisecondsSinceEpoch(ts));
  when(e.senderId).thenReturn('@alice:example.com');
  final user = MockUser();
  when(user.displayName).thenReturn(displayName);
  when(e.senderFromMemoryOrFallback).thenReturn(user);
  return e;
}

Widget _wrap(Widget child) =>
    MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(body: child),);

void main() {
  group('ThreadListTile', () {
    testWidgets('renders preview, reply count, and last reply', (tester) async {
      final root = _event(id: r'$r', body: 'Root msg', ts: 1000);
      final reply =
          _event(id: r'$r2', body: 'Reply text', ts: 2000, displayName: 'Bob');
      final summary = ThreadSummary(
        root: root,
        children: [reply],
        unreadCount: 0,
      );

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () {}),
      ),);

      expect(find.text('Root msg'), findsOneWidget);
      expect(find.text('Bob: Reply text'), findsOneWidget);
      expect(find.text('1 reply'), findsOneWidget);
    });

    testWidgets('shows unread badge when unread > 0', (tester) async {
      final root = _event(id: r'$r', body: 'Root', ts: 1000);
      final reply = _event(id: r'$r2', body: 'Reply', ts: 2000);
      final summary = ThreadSummary(
        root: root,
        children: [reply],
        unreadCount: 3,
      );

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () {}),
      ),);

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('redacted root shows placeholder', (tester) async {
      final root = _event(id: r'$r', body: '', ts: 1000, redacted: true);
      final summary = ThreadSummary(
        root: root,
        children: const [],
        unreadCount: 0,
      );

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () {}),
      ),);

      expect(find.text('[redacted]'), findsOneWidget);
    });

    testWidgets('tap fires onTap', (tester) async {
      var taps = 0;
      final root = _event(id: r'$r', body: 'Root', ts: 1000);
      final summary = ThreadSummary(
        root: root,
        children: const [],
        unreadCount: 0,
      );

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () => taps++),
      ),);

      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });
}

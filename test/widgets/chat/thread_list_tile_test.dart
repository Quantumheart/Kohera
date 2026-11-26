import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_thread_summary.dart';
import 'package:kohera/features/chat/widgets/thread_list_tile.dart';
import 'package:material_ui/material_ui.dart';

KoheraThreadSummary _summary({
  String rootBody = 'Root',
  bool rootRedacted = false,
  int unreadCount = 0,
  int replyCount = 0,
  String? lastReplySenderName,
  String? lastReplyBody,
  bool lastReplyRedacted = false,
}) {
  return KoheraThreadSummary(
    rootEventId: r'$r',
    rootBody: rootBody,
    rootRedacted: rootRedacted,
    rootTimestamp: DateTime.fromMillisecondsSinceEpoch(1000),
    replyCount: replyCount,
    unreadCount: unreadCount,
    lastActivity: DateTime.fromMillisecondsSinceEpoch(2000),
    lastReplySenderName: lastReplySenderName,
    lastReplyBody: lastReplyBody,
    lastReplyRedacted: lastReplyRedacted,
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(body: child),
    );

void main() {
  group('ThreadListTile', () {
    testWidgets('renders preview, reply count, and last reply', (tester) async {
      final summary = _summary(
        rootBody: 'Root msg',
        replyCount: 1,
        lastReplySenderName: 'Bob',
        lastReplyBody: 'Reply text',
      );

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () {}),
      ));

      expect(find.text('Root msg'), findsOneWidget);
      expect(find.text('Bob: Reply text'), findsOneWidget);
      expect(find.text('1 reply'), findsOneWidget);
    });

    testWidgets('shows unread badge when unread > 0', (tester) async {
      final summary = _summary(
        replyCount: 1,
        unreadCount: 3,
        lastReplySenderName: 'Alice',
        lastReplyBody: 'Reply',
      );

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () {}),
      ));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('redacted root shows placeholder', (tester) async {
      final summary = _summary(rootBody: '', rootRedacted: true);

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () {}),
      ));

      expect(find.text('[redacted]'), findsOneWidget);
    });

    testWidgets('tap fires onTap', (tester) async {
      var taps = 0;
      final summary = _summary();

      await tester.pumpWidget(_wrap(
        ThreadListTile(summary: summary, onTap: () => taps++),
      ));

      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_state_event_text.dart';
import 'package:kohera/features/chat/widgets/state_event_tile.dart';

void main() {
  Widget wrap(KoheraStateEventText item) => MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(body: StateEventTile(item: item)),
  );

  testWidgets('renders icon, text and timestamp', (tester) async {
    final item = KoheraStateEventText(
      icon: Icons.login_rounded,
      text: 'Alice joined',
      timestamp: DateTime(2026, 1, 15, 14, 30),
    );

    await tester.pumpWidget(wrap(item));

    expect(find.byIcon(Icons.login_rounded), findsOneWidget);
    expect(find.text('Alice joined'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
  });

  testWidgets('display name change uses previous name as subject', (tester) async {
    final item = KoheraStateEventText(
      icon: Icons.badge_outlined,
      text: "testuser2 changed their display name to 'Bob Ross'",
      timestamp: DateTime(2026, 1, 15, 14, 30),
    );

    await tester.pumpWidget(wrap(item));

    expect(
      find.text("testuser2 changed their display name to 'Bob Ross'"),
      findsOneWidget,
    );
    expect(
      find.text("Bob Ross changed their display name to 'Bob Ross'"),
      findsNothing,
    );
  });

  testWidgets('falls back to MXID localpart when prev displayname is empty', (tester) async {
    final item = KoheraStateEventText(
      icon: Icons.badge_outlined,
      text: "testuser2 changed their display name to 'Bob Ross'",
      timestamp: DateTime(2026, 1, 15, 14, 30),
    );

    await tester.pumpWidget(wrap(item));

    expect(
      find.text("testuser2 changed their display name to 'Bob Ross'"),
      findsOneWidget,
    );
  });

  testWidgets('removing displayname uses previous name as subject', (tester) async {
    final item = KoheraStateEventText(
      icon: Icons.badge_outlined,
      text: 'Old Name removed their display name',
      timestamp: DateTime(2026, 1, 15, 14, 30),
    );

    await tester.pumpWidget(wrap(item));

    expect(find.text('Old Name removed their display name'), findsOneWidget);
  });

  testWidgets('tombstone tile is tappable', (tester) async {
    final item = KoheraStateEventText(
      icon: Icons.upgrade_rounded,
      text: 'This room has been upgraded. Tap to open the new room.',
      timestamp: DateTime(2026, 1, 15, 14, 30),
      replacementRoomId: '!newroom:example.com',
    );

    await tester.pumpWidget(wrap(item));

    expect(item.isTombstone, isTrue);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('non-tombstone tile is not tappable', (tester) async {
    final item = KoheraStateEventText(
      icon: Icons.login_rounded,
      text: 'Alice joined',
      timestamp: DateTime(2026, 1, 15, 14, 30),
    );

    await tester.pumpWidget(wrap(item));

    expect(item.isTombstone, isFalse);
    expect(find.byType(InkWell), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_aliases.dart';
import 'package:kohera/features/rooms/widgets/room_aliases_section.dart';

KoheraRoomAliases _aliases({
  String roomId = '!r:example.com',
  List<String> aliases = const [],
  String? canonicalAlias,
  bool canEdit = true,
  String? homeserverDomain = 'example.com',
}) =>
    KoheraRoomAliases(
      roomId: roomId,
      aliases: aliases,
      canonicalAlias: canonicalAlias,
      canEdit: canEdit,
      homeserverDomain: homeserverDomain,
    );

Widget _wrap(RoomAliasesSection child) => MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  group('RoomAliasesSection', () {
    testWidgets('shows canonical alias when set', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(
              aliases: const ['#room:example.com'],
              canonicalAlias: '#room:example.com',
            ),
            onCreate: (_) async {},
            onDelete: (_) async {},
            onSetCanonical: (_) async {},
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ALIASES'), findsOneWidget);
      expect(find.text('#room:example.com'), findsWidgets);
      expect(find.text('Canonical alias'), findsOneWidget);
    });

    testWidgets('shows no canonical alias placeholder when unset',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(),
            onCreate: (_) async {},
            onDelete: (_) async {},
            onSetCanonical: (_) async {},
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No canonical alias'), findsOneWidget);
    });

    testWidgets('hides create field when cannot edit', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(canEdit: false),
            onCreate: (_) async {},
            onDelete: (_) async {},
            onSetCanonical: (_) async {},
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('create calls onCreate with localpart', (tester) async {
      String? created;
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(),
            onCreate: (local) async => created = local,
            onDelete: (_) async {},
            onSetCanonical: (_) async {},
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'newroom');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(created, 'newroom');
    });

    testWidgets('expands alias list on tap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(
              aliases: const ['#a:example.com', '#b:example.com'],
            ),
            onCreate: (_) async {},
            onDelete: (_) async {},
            onSetCanonical: (_) async {},
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#a:example.com'), findsNothing);
      await tester.tap(find.textContaining('2 aliases'));
      await tester.pumpAndSettle();

      expect(find.text('#a:example.com'), findsOneWidget);
      expect(find.text('#b:example.com'), findsOneWidget);
    });

    testWidgets('delete shows confirmation then calls onDelete', (tester) async {
      String? deleted;
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(
              aliases: const ['#a:example.com'],
              canonicalAlias: '#a:example.com',
            ),
            onCreate: (_) async {},
            onDelete: (alias) async => deleted = alias,
            onSetCanonical: (_) async {},
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('1 alias'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Delete alias?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleted, '#a:example.com');
    });

    testWidgets('set as canonical calls onSetCanonical', (tester) async {
      String? set;
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(
              aliases: const ['#a:example.com', '#b:example.com'],
              canonicalAlias: '#a:example.com',
            ),
            onCreate: (_) async {},
            onDelete: (_) async {},
            onSetCanonical: (alias) async => set = alias,
            onClearCanonical: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('2 aliases'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set as canonical'));
      await tester.pumpAndSettle();

      expect(set, '#b:example.com');
    });

    testWidgets('clear canonical shows confirmation then calls onClearCanonical',
        (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        _wrap(
          RoomAliasesSection(
            aliases: _aliases(
              aliases: const ['#a:example.com'],
              canonicalAlias: '#a:example.com',
            ),
            onCreate: (_) async {},
            onDelete: (_) async {},
            onSetCanonical: (_) async {},
            onClearCanonical: () async => cleared = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Clear canonical alias?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
    });
  });
}

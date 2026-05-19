import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Room>()])
import 'join_access_section_test.mocks.dart';

MockRoom _makeSpace(String id, String name) {
  final r = MockRoom();
  when(r.id).thenReturn(id);
  when(r.getLocalizedDisplayname()).thenReturn(name);
  return r;
}

void main() {
  Widget host({
    required JoinMode mode,
    List<Room> allowed = const [],
    List<Room> candidates = const [],
    bool needsUpgrade = false,
    bool canEdit = true,
    ValueChanged<JoinMode>? onModeChanged,
    ValueChanged<List<Room>>? onAllowedSpacesChanged,
    VoidCallback? onUpgradeRequested,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: JoinAccessSection(
            mode: mode,
            allowedSpaces: allowed,
            candidateSpaces: candidates,
            needsUpgrade: needsUpgrade,
            canEdit: canEdit,
            onModeChanged: onModeChanged ?? (_) {},
            onAllowedSpacesChanged: onAllowedSpacesChanged ?? (_) {},
            onUpgradeRequested: onUpgradeRequested,
          ),
        ),
      ),
    );
  }

  testWidgets('dropdown change invokes onModeChanged', (tester) async {
    JoinMode? captured;
    await tester.pumpWidget(
      host(
        mode: JoinMode.invite,
        onModeChanged: (m) => captured = m,
      ),
    );

    await tester.tap(find.byKey(const Key('join_access_mode_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Space members').last);
    await tester.pumpAndSettle();

    expect(captured, JoinMode.restricted);
  });

  testWidgets(
    'picker hidden for Invite-only / Public / Knock',
    (tester) async {
      for (final mode in [JoinMode.invite, JoinMode.public, JoinMode.knock]) {
        await tester.pumpWidget(host(mode: mode));
        expect(
          find.byKey(const Key('join_access_space_picker')),
          findsNothing,
          reason: 'mode=$mode',
        );
      }
    },
  );

  testWidgets(
    'picker visible for restricted and knockRestricted',
    (tester) async {
      for (final mode in [JoinMode.restricted, JoinMode.knockRestricted]) {
        await tester.pumpWidget(host(
          mode: mode,
          candidates: [_makeSpace('!a:e.com', 'Alpha')],
        ),);
        expect(
          find.byKey(const Key('join_access_space_picker')),
          findsOneWidget,
          reason: 'mode=$mode',
        );
      }
    },
  );

  testWidgets(
    'upgrade banner only shown when needsUpgrade and restricted-family',
    (tester) async {
      await tester.pumpWidget(host(mode: JoinMode.invite, needsUpgrade: true));
      expect(find.byKey(const Key('join_access_upgrade_banner')), findsNothing);

      await tester.pumpWidget(
        host(mode: JoinMode.restricted),
      );
      expect(find.byKey(const Key('join_access_upgrade_banner')), findsNothing);

      await tester.pumpWidget(host(
        mode: JoinMode.restricted,
        needsUpgrade: true,
        candidates: [_makeSpace('!a:e.com', 'Alpha')],
      ),);
      expect(
        find.byKey(const Key('join_access_upgrade_banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets('canEdit:false disables dropdown and upgrade button',
      (tester) async {
    JoinMode? captured;
    var upgradeCalled = false;
    await tester.pumpWidget(host(
      mode: JoinMode.restricted,
      needsUpgrade: true,
      canEdit: false,
      candidates: [_makeSpace('!a:e.com', 'Alpha')],
      onModeChanged: (m) => captured = m,
      onUpgradeRequested: () => upgradeCalled = true,
    ),);

    await tester.tap(
      find.byKey(const Key('join_access_mode_dropdown')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(captured, isNull);

    await tester.tap(
      find.byKey(const Key('join_access_upgrade_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(upgradeCalled, isFalse);
  });

  testWidgets('empty allow list with restricted shows inline error',
      (tester) async {
    await tester.pumpWidget(host(mode: JoinMode.restricted));
    expect(find.byKey(const Key('join_access_empty_error')), findsOneWidget);

    await tester.pumpWidget(host(
      mode: JoinMode.restricted,
      candidates: [_makeSpace('!a:e.com', 'Alpha')],
      allowed: [_makeSpace('!a:e.com', 'Alpha')],
    ),);
    expect(find.byKey(const Key('join_access_empty_error')), findsNothing);
  });

  testWidgets('checking a space candidate fires onAllowedSpacesChanged',
      (tester) async {
    List<Room>? captured;
    final alpha = _makeSpace('!a:e.com', 'Alpha');
    await tester.pumpWidget(host(
      mode: JoinMode.restricted,
      candidates: [alpha],
      onAllowedSpacesChanged: (l) => captured = l,
    ),);

    await tester.tap(find.byKey(const Key('join_access_space_!a:e.com')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.map((r) => r.id), ['!a:e.com']);
  });
}

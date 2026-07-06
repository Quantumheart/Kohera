import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/features/rooms/services/join_access_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<SpaceAccessService>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'join_access_controller_test.mocks.dart';

void main() {
  late MockMatrixService matrix;
  late MockSpaceAccessService access;
  late MockClient client;
  late SelectionService selection;
  late MockRoom room;

  setUp(() {
    matrix = MockMatrixService();
    access = MockSpaceAccessService();
    client = MockClient();
    room = MockRoom();

    when(matrix.client).thenReturn(client);
    when(matrix.spaceAccess).thenReturn(access);
    when(client.rooms).thenReturn([]);
    when(client.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    selection = SelectionService(client: client);
    when(matrix.selection).thenReturn(selection);

    when(room.id).thenReturn('!r:e.com');
    when(client.getRoomById('!r:e.com')).thenReturn(room);
    when(room.canChangeStateEvent(EventTypes.RoomJoinRules)).thenReturn(true);
    when(access.getJoinMode(room)).thenReturn(JoinMode.invite);
    when(access.allowedSpaceIds(room)).thenReturn(const []);
    when(access.needsUpgradeForRestricted(room, wantKnock: anyNamed('wantKnock')))
        .thenReturn(false);
  });

  Widget host({CandidateSpacesBuilder? candidatesBuilder}) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChangeNotifierProvider<MatrixService>.value(
            value: matrix,
            child: JoinAccessController(
              roomId: room.id,
              candidatesBuilder: candidatesBuilder,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('mode change invokes applyJoinMode', (tester) async {
    when(
      access.applyJoinMode(
        roomId: anyNamed('roomId'),
        mode: anyNamed('mode'),
        allowSpaceIds: anyNamed('allowSpaceIds'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(host());

    await tester.tap(find.byKey(const Key('join_access_mode_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public').last);
    await tester.pumpAndSettle();
    // Auto-save is debounced — advance past the timer.
    await tester.pump(const Duration(milliseconds: 600));

    verify(
      access.applyJoinMode(
        roomId: '!r:e.com',
        mode: JoinMode.public,
        allowSpaceIds: anyNamed('allowSpaceIds'),
      ),
    ).called(1);
  });

  testWidgets('PL too low disables dropdown', (tester) async {
    when(room.canChangeStateEvent(EventTypes.RoomJoinRules)).thenReturn(false);
    await tester.pumpWidget(host());

    expect(find.byTooltip('Requires higher power level'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('join_access_mode_dropdown')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    verifyNever(
      access.applyJoinMode(
        roomId: anyNamed('roomId'),
        mode: anyNamed('mode'),
        allowSpaceIds: anyNamed('allowSpaceIds'),
      ),
    );
  });

  testWidgets('custom candidatesBuilder controls picker entries',
      (tester) async {
    when(access.getJoinMode(room)).thenReturn(JoinMode.restricted);
    when(access.allowedSpaceIds(room)).thenReturn(const []);
    final parent = MockRoom();
    when(parent.id).thenReturn('!parent:e.com');
    when(parent.getLocalizedDisplayname()).thenReturn('Parent');

    await tester.pumpWidget(host(candidatesBuilder: (_, _) => [(id: '!parent:e.com', displayname: 'Parent')]));

    expect(
      find.byKey(const Key('join_access_space_!parent:e.com')),
      findsOneWidget,
    );
  });

  testWidgets('empty candidates shows no-parents hint', (tester) async {
    when(access.getJoinMode(room)).thenReturn(JoinMode.restricted);

    await tester.pumpWidget(host(candidatesBuilder: (_, _) => const []));

    expect(find.text('No eligible parent spaces'), findsOneWidget);
  });

  testWidgets(
    'empty candidates disables restricted dropdown items with tooltip',
    (tester) async {
      await tester.pumpWidget(host(candidatesBuilder: (_, _) => const []));

      final innerDropdown = tester.widget<DropdownButton<JoinMode>>(
        find.descendant(
          of: find.byKey(const Key('join_access_mode_dropdown')),
          matching: find.byType(DropdownButton<JoinMode>),
        ),
      );
      final restrictedItem = innerDropdown.items!.firstWhere(
        (i) => i.value == JoinMode.restricted,
      );
      final knockItem = innerDropdown.items!.firstWhere(
        (i) => i.value == JoinMode.knockRestricted,
      );
      expect(restrictedItem.enabled, isFalse);
      expect(knockItem.enabled, isFalse);
    },
  );

  testWidgets('sync update refreshes mode when not user-dirty',
      (tester) async {
    final controller = CachedStreamController<SyncUpdate>();
    when(client.onSync).thenReturn(controller);

    when(access.getJoinMode(room)).thenReturn(JoinMode.invite);
    await tester.pumpWidget(host());
    expect(find.text('Invite-only'), findsWidgets);

    // Server-side flip.
    when(access.getJoinMode(room)).thenReturn(JoinMode.public);
    controller.add(SyncUpdate(nextBatch: ''));
    await tester.pump();

    expect(find.text('Public'), findsWidgets);
  });

  testWidgets('saving spinner appears during applyJoinMode',
      (tester) async {
    final completer = Completer<void>();
    when(
      access.applyJoinMode(
        roomId: anyNamed('roomId'),
        mode: anyNamed('mode'),
        allowSpaceIds: anyNamed('allowSpaceIds'),
      ),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(host());

    await tester.tap(find.byKey(const Key('join_access_mode_dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Public').last);
    await tester.pump();
    // Fire the debounce timer and let _applyIfValid kick off.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(
      find.byKey(const Key('join_access_saving_indicator')),
      findsOneWidget,
    );

    completer.complete();
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('join_access_saved_indicator')),
      findsOneWidget,
    );
    // Drain the saved-hint timer before tearing down.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'upgrade banner click triggers upgrade + rewire + apply',
    (tester) async {
      when(access.getJoinMode(room)).thenReturn(JoinMode.restricted);
      final allowSpace = MockRoom();
      when(allowSpace.id).thenReturn('!s:e.com');
      when(allowSpace.isSpace).thenReturn(true);
      when(allowSpace.membership).thenReturn(Membership.join);
      when(allowSpace.getLocalizedDisplayname()).thenReturn('Alpha');
      when(access.allowedSpaceIds(room)).thenReturn(['!s:e.com']);
      when(client.getRoomById('!s:e.com')).thenReturn(allowSpace);
      when(client.rooms).thenReturn([allowSpace]);
      when(
        access.needsUpgradeForRestricted(room,
            wantKnock: anyNamed('wantKnock'),),
      ).thenReturn(true);
      when(access.pickRestrictedRoomVersion(wantKnock: false))
          .thenAnswer((_) async => '10');
      when(access.pickRestrictedRoomVersion(wantKnock: true))
          .thenAnswer((_) async => '10');
      when(access.upgradeRoomTo(room, '10'))
          .thenAnswer((_) async => '!newroom:e.com');
      when(client.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(access.rewireParentSpaces(
        oldRoomId: anyNamed('oldRoomId'),
        newRoomId: anyNamed('newRoomId'),
        parents: anyNamed('parents'),
      ),).thenAnswer((_) async {});
      when(
        access.applyJoinMode(
          roomId: anyNamed('roomId'),
          mode: anyNamed('mode'),
          allowSpaceIds: anyNamed('allowSpaceIds'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(host());

      expect(
        find.byKey(const Key('join_access_upgrade_banner')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('join_access_upgrade_button')));
      await tester.pumpAndSettle();

      // confirm dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Upgrade'));
      await tester.pumpAndSettle();

      verify(access.upgradeRoomTo(room, '10')).called(1);
      verify(access.rewireParentSpaces(
        oldRoomId: '!r:e.com',
        newRoomId: '!newroom:e.com',
        parents: anyNamed('parents'),
      ),).called(1);
      verify(
        access.applyJoinMode(
          roomId: '!newroom:e.com',
          mode: JoinMode.restricted,
          allowSpaceIds: ['!s:e.com'],
        ),
      ).called(1);
    },
  );
}

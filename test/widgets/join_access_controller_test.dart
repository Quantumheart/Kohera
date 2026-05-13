import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/features/rooms/widgets/join_access_controller.dart';
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
    when(room.canChangeStateEvent(EventTypes.RoomJoinRules)).thenReturn(true);
    when(access.getJoinMode(room)).thenReturn(JoinMode.invite);
    when(access.allowedSpaceIds(room)).thenReturn(const []);
    when(access.needsUpgradeForRestricted(room, wantKnock: anyNamed('wantKnock')))
        .thenReturn(false);
  });

  Widget host({CandidateSpacesBuilder? candidatesBuilder}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChangeNotifierProvider<MatrixService>.value(
            value: matrix,
            child: JoinAccessController(
              room: room,
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

    await tester.pumpWidget(host(candidatesBuilder: (_, __) => [parent]));

    expect(
      find.byKey(const Key('join_access_space_!parent:e.com')),
      findsOneWidget,
    );
  });

  testWidgets('empty candidates shows no-parents hint', (tester) async {
    when(access.getJoinMode(room)).thenReturn(JoinMode.restricted);

    await tester.pumpWidget(host(candidatesBuilder: (_, __) => const []));

    expect(find.text('No eligible parent spaces'), findsOneWidget);
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
      when(access.upgradeRoomTo(room, '10'))
          .thenAnswer((_) async => '!newroom:e.com');
      when(access.rewireParentSpaces('!r:e.com', '!newroom:e.com'))
          .thenAnswer((_) async {});
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
      verify(access.rewireParentSpaces('!r:e.com', '!newroom:e.com')).called(1);
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

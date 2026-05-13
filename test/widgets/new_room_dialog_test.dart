import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/features/rooms/widgets/new_room_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<SpaceAccessService>(),
  MockSpec<Room>(),
])
import 'new_room_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockSpaceAccessService mockAccess;

  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockAccess = MockSpaceAccessService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockMatrixService.spaceAccess).thenReturn(mockAccess);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
  });

  MockRoom makeSpace(String id, String name) {
    final r = MockRoom();
    when(r.id).thenReturn(id);
    when(r.isSpace).thenReturn(true);
    when(r.membership).thenReturn(Membership.join);
    when(r.getLocalizedDisplayname()).thenReturn(name);
    when(r.spaceChildren).thenReturn([]);
    when(r.canChangeStateEvent('m.space.child')).thenReturn(true);
    return r;
  }

  Widget buildTestWidget({Set<String>? parentSpaceIds}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                unawaited(NewRoomDialog.show(
                  context,
                  matrixService: mockMatrixService,
                  parentSpaceIds: parentSpaceIds,
                ),);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    Set<String>? parentSpaceIds,
  }) async {
    await tester.pumpWidget(buildTestWidget(parentSpaceIds: parentSpaceIds));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('NewRoomDialog', () {
    testWidgets('shows name required error when submitting empty',
        (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('calls createRoom with correct parameters', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenAnswer((_) async => '!newroom:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Test Room',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Topic (optional)'),
        'A test topic',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'Test Room',
        topic: 'A test topic',
        visibility: Visibility.private,
        initialState: anyNamed('initialState'),
      ),).called(1);
      verify(mockClient.waitForRoomInSync('!newroom:example.com', join: true))
          .called(1);
      expect(selectionService.selectedRoomId, '!newroom:example.com');
    });

    testWidgets('shows network error on failure', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenThrow(Exception('Server error'));
      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Test Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Dialog should still be open with error
      expect(find.text('New Room'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Room'), findsNothing);
    });

    testWidgets('public room toggle changes visibility', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenAnswer((_) async => '!newroom:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await openDialog(tester);

      // Toggle public room switch
      await tester.tap(find.text('Public room'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Public Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'Public Room',
        visibility: Visibility.public,
        initialState: anyNamed('initialState'),
      ),).called(1);
    });

    testWidgets(
      'parent space context preselects restricted with initial_state',
      (tester) async {
        final parent = makeSpace('!parent:e.com', 'Parent');
        when(mockClient.getRoomById('!parent:e.com')).thenReturn(parent);
        when(mockClient.rooms).thenReturn([parent]);
        when(mockAccess.pickRestrictedRoomVersion(wantKnock: true))
            .thenAnswer((_) async => '10');
        when(mockAccess.pickRestrictedRoomVersion(wantKnock: false))
            .thenAnswer((_) async => '10');
        when(mockAccess.buildJoinRulesStateEvent(any, any)).thenReturn(
          StateEvent(
            type: EventTypes.RoomJoinRules,
            content: {
              'join_rule': 'restricted',
              'allow': [
                {'type': 'm.room_membership', 'room_id': '!parent:e.com'},
              ],
            },
          ),
        );
        when(
          mockClient.createRoom(
            name: anyNamed('name'),
            topic: anyNamed('topic'),
            visibility: anyNamed('visibility'),
            roomVersion: anyNamed('roomVersion'),
            initialState: anyNamed('initialState'),
            invite: anyNamed('invite'),
          ),
        ).thenAnswer((_) async => '!newroom:e.com');
        when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
            .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

        await openDialog(tester, parentSpaceIds: {'!parent:e.com'});

        expect(find.text('Space members'), findsWidgets);

        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'Restricted Room',
        );
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        final captured = verify(
          mockClient.createRoom(
            name: 'Restricted Room',
            topic: anyNamed('topic'),
            visibility: Visibility.private,
            roomVersion: '10',
            initialState: captureAnyNamed('initialState'),
            invite: anyNamed('invite'),
          ),
        ).captured.single as List<StateEvent>;
        final joinRules = captured.firstWhere(
          (s) => s.type == EventTypes.RoomJoinRules,
        );
        expect(joinRules.content['join_rule'], 'restricted');
        expect(joinRules.content['allow'], [
          {'type': 'm.room_membership', 'room_id': '!parent:e.com'},
        ]);
      },
    );

    testWidgets('server lacking v8 hides the section', (tester) async {
      final parent = makeSpace('!parent:e.com', 'Parent');
      when(mockClient.getRoomById('!parent:e.com')).thenReturn(parent);
      when(mockClient.rooms).thenReturn([parent]);
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: anyNamed('wantKnock')))
          .thenAnswer((_) async => null);

      await openDialog(tester, parentSpaceIds: {'!parent:e.com'});

      expect(find.text('Space members'), findsNothing);
      expect(find.text('Space members + knock'), findsNothing);
    });

    testWidgets('v8 but no v10 disables knock_restricted option',
        (tester) async {
      final parent = makeSpace('!parent:e.com', 'Parent');
      when(mockClient.getRoomById('!parent:e.com')).thenReturn(parent);
      when(mockClient.rooms).thenReturn([parent]);
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: true))
          .thenAnswer((_) async => null);
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: false))
          .thenAnswer((_) async => '8');

      await openDialog(tester, parentSpaceIds: {'!parent:e.com'});

      final innerDropdown = tester.widget<DropdownButton<JoinMode>>(
        find.descendant(
          of: find.byKey(const Key('join_access_mode_dropdown')),
          matching: find.byType(DropdownButton<JoinMode>),
        ),
      );
      final knockItem = innerDropdown.items!.firstWhere(
        (i) => i.value == JoinMode.knockRestricted,
      );
      expect(knockItem.enabled, isFalse);
      final restrictedItem = innerDropdown.items!.firstWhere(
        (i) => i.value == JoinMode.restricted,
      );
      expect(restrictedItem.enabled, isTrue);
    });

    testWidgets('invite chips can be added and removed', (tester) async {
      await openDialog(tester);

      // Add an invite
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite users (optional)'),
        '@alice:example.com',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('@alice:example.com'), findsOneWidget);

      // Remove it via chip delete
      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, '@alice:example.com'), findsNothing);
    });
  });
}

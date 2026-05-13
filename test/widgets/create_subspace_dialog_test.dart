import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<SpaceAccessService>(),
])
import 'create_subspace_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockParentSpace;
  late MockSpaceAccessService mockAccess;

  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockParentSpace = MockRoom();
    mockAccess = MockSpaceAccessService();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
    when(mockMatrixService.spaceAccess).thenReturn(mockAccess);
    when(mockAccess.pickRestrictedRoomVersion(
      wantKnock: anyNamed('wantKnock'),
    ),).thenAnswer((_) async => null);
    when(mockParentSpace.getLocalizedDisplayname())
        .thenReturn('Parent Space');
    when(mockParentSpace.id).thenReturn('!parent:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => CreateSubspaceDialog.show(
              context,
              matrixService: mockMatrixService,
              parentSpace: mockParentSpace,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows name and topic fields with parent space context',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Create subspace'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(
        find.widgetWithText(TextField, 'Topic (optional)'), findsOneWidget,);
    expect(find.textContaining('Parent Space'), findsOneWidget);
  });

  testWidgets('validates empty name', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('submitting calls createRoom and setSpaceChild', (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      roomVersion: anyNamed('roomVersion'),
      initialState: anyNamed('initialState'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).thenAnswer((_) async => '!subspace:example.com');

    when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
        .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

    await openDialog(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'My Subspace',);
    await tester.enterText(
        find.widgetWithText(TextField, 'Topic (optional)'), 'A topic',);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    verify(mockClient.createRoom(
      name: 'My Subspace',
      topic: 'A topic',
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      roomVersion: anyNamed('roomVersion'),
      initialState: anyNamed('initialState'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).called(1);

    verify(mockParentSpace.setSpaceChild('!subspace:example.com')).called(1);

    // Dialog should close on success.
    expect(find.text('Create subspace'), findsNothing);
  });

  testWidgets('shows error on failure', (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      roomVersion: anyNamed('roomVersion'),
      initialState: anyNamed('initialState'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).thenThrow(Exception('Server error'));

    await openDialog(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Bad Subspace',);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Server error'), findsOneWidget);
    // Dialog should remain open.
    expect(find.text('Create subspace'), findsOneWidget);
  });

  testWidgets(
    'restricted-capable server creates subspace with join_rules initial_state',
    (tester) async {
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: true))
          .thenAnswer((_) async => '10');
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: false))
          .thenAnswer((_) async => '10');
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        visibility: anyNamed('visibility'),
        roomVersion: anyNamed('roomVersion'),
        initialState: anyNamed('initialState'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).thenAnswer((_) async => '!sub:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Gated',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final captured = verify(mockClient.createRoom(
        name: 'Gated',
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        visibility: anyNamed('visibility'),
        roomVersion: '10',
        initialState: captureAnyNamed('initialState'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).captured.single as List<StateEvent>;
      final joinRules = captured.firstWhere(
        (s) => s.type == EventTypes.RoomJoinRules,
      );
      expect(joinRules.content['join_rule'], 'restricted');
      expect(joinRules.content['allow'], [
        {'type': 'm.room_membership', 'room_id': '!parent:example.com'},
      ]);
    },
  );

  testWidgets('cancel closes dialog', (tester) async {
    await openDialog(tester);

    expect(find.text('Create subspace'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Create subspace'), findsNothing);
  });
}

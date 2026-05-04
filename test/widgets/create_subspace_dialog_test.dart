import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'create_subspace_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockParentSpace;

  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockParentSpace = MockRoom();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
    when(mockParentSpace.getLocalizedDisplayname())
        .thenReturn('Parent Space');
    when(mockParentSpace.id).thenReturn('!parent:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: const MediaQueryData(size: Size(900, 900)),
        child: child!,
      ),
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

  Future<void> advanceToStep3(WidgetTester tester, String name) async {
    await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  testWidgets('title shows parent space name', (tester) async {
    await openDialog(tester);
    expect(find.textContaining('Parent Space'), findsOneWidget);
  });

  testWidgets('federation defaults on for subspace', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'X');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    final fedSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Allow federation'),
    );
    expect(fedSwitch.value, isTrue);
  });

  testWidgets('Next disabled until name entered', (tester) async {
    await openDialog(tester);
    final nextBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Next'),
    );
    expect(nextBtn.onPressed, isNull);
  });

  testWidgets('create calls createRoom + setSpaceChild, no selectSpace',
      (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).thenAnswer((_) async => '!subspace:example.com');
    when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
        .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

    await openDialog(tester);
    await advanceToStep3(tester, 'My Subspace');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    verify(mockClient.createRoom(
      name: 'My Subspace',
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).called(1);
    verify(mockParentSpace.setSpaceChild('!subspace:example.com')).called(1);
    expect(selectionService.selectedSpaceIds,
        isNot(contains('!subspace:example.com')),);
  });

  testWidgets('child-link failure shows snackbar, space still created',
      (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).thenAnswer((_) async => '!sub:example.com');
    when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
        .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
    when(mockParentSpace.setSpaceChild(any))
        .thenThrow(Exception('forbidden'));

    await openDialog(tester);
    await advanceToStep3(tester, 'X');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to add to parent space'), findsOneWidget);
  });

  testWidgets('shows error on createRoom failure', (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).thenThrow(Exception('Server error'));

    await openDialog(tester);
    await advanceToStep3(tester, 'Bad');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Server error'), findsOneWidget);
  });

  testWidgets('cancel closes dialog', (tester) async {
    await openDialog(tester);
    expect(find.textContaining('Parent Space'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Parent Space'), findsNothing);
  });
}

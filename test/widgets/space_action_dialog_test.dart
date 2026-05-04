import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'space_action_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
  });

  Widget buildTestWidget({Size size = const Size(900, 800)}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQueryData(size: size),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => CreateSpaceDialog.show(
                context,
                matrixService: mockMatrixService,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openWizard(WidgetTester tester, {Size? size}) async {
    final effective = size ?? const Size(900, 900);
    await tester.pumpWidget(buildTestWidget(size: effective));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> advanceToStep3(WidgetTester tester, {String name = 'My Space'}) async {
    await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  void stubCreateRoom(String roomId) {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    ),).thenAnswer((_) async => roomId);
    when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
        .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
  }

  group('CreateSpaceDialog wizard', () {
    testWidgets('step 1 shows name, topic, avatar picker', (tester) async {
      await openWizard(tester);

      expect(find.text('Create Space'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Topic (optional)'), findsOneWidget);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });

    testWidgets('Next disabled until name entered', (tester) async {
      await openWizard(tester);

      final nextBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(nextBtn.onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Hi');
      await tester.pump();

      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('step 2 has visibility + federation, no encryption switch',
        (tester) async {
      await openWizard(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'X');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      expect(find.text('Public space'), findsOneWidget);
      expect(find.text('Allow federation'), findsOneWidget);
      expect(find.text('Enable encryption'), findsNothing);
    });

    testWidgets('step 3 shows placeholder + Create button', (tester) async {
      await openWizard(tester);
      await advanceToStep3(tester);

      expect(find.textContaining('Coming in the next release'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
    });

    testWidgets('step state preserved across Back/Next', (tester) async {
      await openWizard(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Name'), 'Persisted',);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Name'),
      );
      expect(field.controller!.text, 'Persisted');
    });

    testWidgets(
        'create with federation off sends m.federate:false, no encryption',
        (tester) async {
      stubCreateRoom('!new:example.com');

      await openWizard(tester);
      await advanceToStep3(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final captured = verify(mockClient.createRoom(
        name: 'My Space',
        topic: anyNamed('topic'),
        creationContent: captureAnyNamed('creationContent'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).captured.single as Map<String, dynamic>;
      expect(captured['type'], 'm.space');
      expect(captured['m.federate'], false);

      verifyNever(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),);
      expect(selectionService.selectedSpaceIds, contains('!new:example.com'));
    });

    testWidgets('create with federation on omits m.federate key',
        (tester) async {
      stubCreateRoom('!new2:example.com');

      await openWizard(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'F');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Allow federation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final captured = verify(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: captureAnyNamed('creationContent'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).captured.single as Map<String, dynamic>;
      expect(captured.containsKey('m.federate'), isFalse);
    });

    testWidgets('shows error on createRoom failure', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).thenThrow(Exception('Server error'));

      await openWizard(tester);
      await advanceToStep3(tester, name: 'Bad');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
      expect(find.text('Create Space'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await openWizard(tester);
      expect(find.text('Create Space'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsNothing);
    });

    testWidgets('narrow surface uses fullscreen Dialog', (tester) async {
      await openWizard(tester, size: const Size(500, 800));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('wide surface uses AlertDialog', (tester) async {
      await openWizard(tester, size: const Size(900, 800));

      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('JoinSpaceDialog', () {
    Widget buildJoinTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
          ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => JoinSpaceDialog.show(
                  context,
                  matrixService: mockMatrixService,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows address field', (tester) async {
      await tester.pumpWidget(buildJoinTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join Space'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Space address'), findsOneWidget);
    });

    testWidgets('validates empty address', (tester) async {
      await tester.pumpWidget(buildJoinTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.text('Address is required'), findsOneWidget);
    });

    testWidgets('submitting calls client.joinRoom', (tester) async {
      final mockSpace = MockRoom();
      when(mockSpace.isSpace).thenReturn(true);

      when(mockClient.joinRoom(any))
          .thenAnswer((_) async => '!space:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(mockClient.getRoomById('!space:example.com')).thenReturn(mockSpace);

      await tester.pumpWidget(buildJoinTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Space address'),
        '#myspace:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      verify(mockClient.joinRoom('#myspace:example.com')).called(1);
      expect(selectionService.selectedSpaceIds, contains('!space:example.com'));
    });

    testWidgets('shows error on join failure', (tester) async {
      when(mockClient.joinRoom(any)).thenThrow(Exception('Room not found'));

      await tester.pumpWidget(buildJoinTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Space address'),
        '#bad:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Room not found'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildJoinTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join Space'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Join Space'), findsNothing);
    });
  });
}

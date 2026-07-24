import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
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

  group('CreateSpaceDialog', () {
    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
          ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
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

    testWidgets('shows name and topic fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Topic (optional)'), findsOneWidget);
    });

    testWidgets('shows toggle switches', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Public space'), findsOneWidget);
      expect(find.text('Enable encryption'), findsOneWidget);
      expect(find.text('Allow federation'), findsOneWidget);
    });

    testWidgets('validates empty name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('submitting calls client.createRoom and selects space', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).thenAnswer((_) async => '!newspace:example.com');

      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'My Space');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'My Space',
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).called(1);

      expect(selectionService.selectedSpaceIds, contains('!newspace:example.com'));
    });

    testWidgets('shows error on failure', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      ),).thenThrow(Exception('Server error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Bad Space');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('toggling public disables encryption', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Toggle public space on
      await tester.tap(find.widgetWithText(SwitchListTile, 'Public space'));
      await tester.pumpAndSettle();

      expect(find.text('Not available for public spaces'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsNothing);
    });
  });

  group('JoinWithAddressDialog', () {
    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
          ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => JoinWithAddressDialog.show(
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
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join with address'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Room or space address'),
        findsOneWidget,
      );
    });

    testWidgets('rejects a non-matrix address', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room or space address'),
        'not a room',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter a room alias'), findsOneWidget);
      verifyNever(mockClient.joinRoom(any, via: anyNamed('via')));
    });

    testWidgets('validates empty address', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.text('Address is required'), findsOneWidget);
    });

    testWidgets('submitting a space selects the space', (tester) async {
      final mockSpace = MockRoom();
      when(mockSpace.isSpace).thenReturn(true);

      when(mockClient.joinRoom(any, via: anyNamed('via')))
          .thenAnswer((_) async => '!space:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(mockClient.getRoomById('!space:example.com')).thenReturn(mockSpace);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room or space address'),
        '#myspace:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      verify(
        mockClient.joinRoom('#myspace:example.com', via: anyNamed('via')),
      ).called(1);
      expect(selectionService.selectedSpaceIds, contains('!space:example.com'));
    });

    testWidgets('submitting a regular room navigates to the room',
        (tester) async {
      final mockRoom = MockRoom();
      when(mockRoom.isSpace).thenReturn(false);

      when(mockClient.joinRoom(any, via: anyNamed('via')))
          .thenAnswer((_) async => '!room:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      String? navigatedRoom;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: ElevatedButton(
                onPressed: () => JoinWithAddressDialog.show(
                  context,
                  matrixService: mockMatrixService,
                ),
                child: const Text('Open'),
              ),
            ),
            routes: [
              GoRoute(
                path: RouteSegments.room,
                name: Routes.room,
                builder: (context, state) {
                  navigatedRoom = state.pathParameters[RouteParams.roomId];
                  return Scaffold(
                    body: Text(
                      'Room ${state.pathParameters[RouteParams.roomId]}',
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MatrixService>.value(
              value: mockMatrixService,
            ),
            ChangeNotifierProvider<SelectionService>.value(
              value: selectionService,
            ),
          ],
          child: MaterialApp.router(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room or space address'),
        '#general:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      verify(
        mockClient.joinRoom('#general:example.com', via: anyNamed('via')),
      ).called(1);
      // A regular room is selected as a room (not a space)…
      expect(selectionService.selectedRoomId, '!room:example.com');
      expect(
        selectionService.selectedSpaceIds,
        isNot(contains('!room:example.com')),
      );
      // …and the router navigated to the room screen.
      expect(navigatedRoom, '!room:example.com');
      expect(find.text('Room !room:example.com'), findsOneWidget);
    });

    testWidgets('passes via servers from a matrix.to link', (tester) async {
      final mockSpace = MockRoom();
      when(mockSpace.isSpace).thenReturn(true);
      when(mockClient.joinRoom(any, via: anyNamed('via')))
          .thenAnswer((_) async => '!space:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(mockClient.getRoomById('!space:example.com')).thenReturn(mockSpace);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room or space address'),
        'https://matrix.to/#/#space:example.com?via=s1.org&via=s2.org',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      verify(
        mockClient.joinRoom(
          '#space:example.com',
          via: argThat(equals(['s1.org', 's2.org']), named: 'via'),
        ),
      ).called(1);
    });

    testWidgets('shows error on join failure', (tester) async {
      when(mockClient.joinRoom(any, via: anyNamed('via')))
          .thenThrow(Exception('Room not found'));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room or space address'),
        '#bad:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Room not found'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join with address'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Join with address'), findsNothing);
    });
  });

  group('SpaceDiscoveryDialog.showSpaceRooms', () {
    late FakeSpaceDiscoveryDataSource dataSource;

    setUp(() {
      dataSource = FakeSpaceDiscoveryDataSource(delay: Duration.zero);
    });

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(
            value: mockMatrixService,
          ),
          ChangeNotifierProvider<SelectionService>.value(
            value: selectionService,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => SpaceDiscoveryDialog.showSpaceRooms(
                  context,
                  matrixService: mockMatrixService,
                  roomId: '!fake-space-0:example.org',
                  name: 'Quantum HQ',
                  dataSource: dataSource,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('opens directly to space preview', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Explore spaces'), findsNothing);
      expect(find.text('Quantum HQ'), findsWidgets);
      expect(find.text('Rooms in this space'), findsOneWidget);
    });

    testWidgets('shows Open header for a joined space', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.runAsync(() => dataSource.joinRoom('!fake-space-0:example.org'));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join space'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Open'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows Join for unjoined child rooms', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.runAsync(() => dataSource.joinRoom('!fake-space-0:example.org'));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsAtLeastNWidgets(1));
    });

    testWidgets('back button closes seeded preview', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.runAsync(() => dataSource.joinRoom('!fake-space-0:example.org'));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Quantum HQ'), findsWidgets);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Quantum HQ'), findsNothing);
      expect(find.text('Explore spaces'), findsNothing);
    });
  });
}

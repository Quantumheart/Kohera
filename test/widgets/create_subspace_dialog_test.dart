import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_action.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
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

const _defaultCaps = SubspaceCapabilities(
  restrictedRoomVersion: null,
  disabledModes: {JoinMode.knockRestricted: 'Not supported by this server'},
);

SpaceRef _parentRef(String name) =>
    (id: '!parent:example.com', displayname: name);

void main() {
  // ── Dialog UI tests (SDK-free, callback-based) ──────────────────────

  Widget buildTestWidget({
    required Future<void> Function(CreateSubspaceRequest request)
        onCreateSubspace,
    SubspaceCapabilities caps = _defaultCaps,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => CreateSubspaceDialog.show(
              context,
              parentSpaceRef: _parentRef('Parent Space'),
              loadCapabilities: () async => caps,
              onCreateSubspace: onCreateSubspace,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidget(onCreateSubspace: (request) async {}),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('CreateSubspaceDialog', () {
    testWidgets('shows name and topic fields with parent space context',
        (tester) async {
      await openDialog(tester);

      expect(find.text('Create subspace'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Topic (optional)'),
        findsOneWidget,
      );
      expect(find.textContaining('Parent Space'), findsOneWidget);
    });

    testWidgets('validates empty name', (tester) async {
      await openDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('submitting calls onCreateSubspace with the request and closes',
        (tester) async {
      CreateSubspaceRequest? captured;
      await tester.pumpWidget(
        buildTestWidget(
          onCreateSubspace: (request) async {
            captured = request;
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My Subspace',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Topic (optional)'),
        'A topic',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.name, 'My Subspace');
      expect(captured!.topic, 'A topic');
      expect(find.text('Create subspace'), findsNothing);
    });

    testWidgets('shows error on failure', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          onCreateSubspace: (request) async => throw Exception('Server error'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Bad Subspace',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
      expect(find.text('Create subspace'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create subspace'), findsNothing);
    });

    testWidgets(
      'restricted-capable server shows join access section and submits '
      'restricted request',
      (tester) async {
        CreateSubspaceRequest? captured;
        await tester.pumpWidget(
          buildTestWidget(
            caps: const SubspaceCapabilities(
              restrictedRoomVersion: '10',
              disabledModes: {},
            ),
            onCreateSubspace: (request) async {
              captured = request;
            },
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('join_access_mode_dropdown')),
          findsOneWidget,
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'Gated',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.joinMode, JoinMode.restricted);
        expect(captured!.allowedSpaceIds, ['!parent:example.com']);
        expect(captured!.restrictedRoomVersion, '10');
      },
    );
  });

  // ── Helper tests (SDK create flow) ─────────────────────────────────

  group('createSubspace action', () {
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
      when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
      selectionService = SelectionService(client: mockClient);
      when(mockMatrixService.client).thenReturn(mockClient);
      when(mockMatrixService.selection).thenReturn(selectionService);
      when(mockMatrixService.spaceAccess).thenReturn(mockAccess);
      when(mockParentSpace.id).thenReturn('!parent:example.com');
      when(mockClient.getRoomById('!parent:example.com'))
          .thenReturn(mockParentSpace);

      when(
        mockClient.createRoom(
          name: anyNamed('name'),
          topic: anyNamed('topic'),
          creationContent: anyNamed('creationContent'),
          visibility: anyNamed('visibility'),
          roomVersion: anyNamed('roomVersion'),
          initialState: anyNamed('initialState'),
          powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
        ),
      ).thenAnswer((_) async => '!subspace:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
    });

    test('calls createRoom and setSpaceChild', () async {
      await createSubspace(
        mockMatrixService,
        mockParentSpace.id,
        const CreateSubspaceRequest(
          name: 'My Subspace',
          topic: 'A topic',
          joinMode: JoinMode.invite,
          allowedSpaceIds: [],
          restrictedRoomVersion: null,
        ),
      );

      verify(
        mockClient.createRoom(
          name: 'My Subspace',
          topic: 'A topic',
          creationContent: anyNamed('creationContent'),
          visibility: anyNamed('visibility'),
          roomVersion: anyNamed('roomVersion'),
          initialState: anyNamed('initialState'),
          powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
        ),
      ).called(1);

      verify(mockParentSpace.setSpaceChild('!subspace:example.com')).called(1);
    });

    test('restricted request creates subspace with join_rules initial_state',
        () async {
      when(mockAccess.buildJoinRulesStateEvent(any, any)).thenReturn(
        StateEvent(
          type: EventTypes.RoomJoinRules,
          content: {
            'join_rule': 'restricted',
            'allow': [
              {'type': 'm.room_membership', 'room_id': '!parent:example.com'},
            ],
          },
        ),
      );

      await createSubspace(
        mockMatrixService,
        mockParentSpace.id,
        const CreateSubspaceRequest(
          name: 'Gated',
          topic: null,
          joinMode: JoinMode.restricted,
          allowedSpaceIds: ['!parent:example.com'],
          restrictedRoomVersion: '10',
        ),
      );

      final captured = verify(
        mockClient.createRoom(
          name: 'Gated',
          topic: anyNamed('topic'),
          creationContent: anyNamed('creationContent'),
          visibility: anyNamed('visibility'),
          roomVersion: '10',
          initialState: captureAnyNamed('initialState'),
          powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
        ),
      ).captured.single as List<StateEvent>;
      final joinRules =
          captured.firstWhere((s) => s.type == EventTypes.RoomJoinRules);
      expect(joinRules.content['join_rule'], 'restricted');
      expect(
        joinRules.content['allow'],
        [
          {'type': 'm.room_membership', 'room_id': '!parent:example.com'},
        ],
      );
    });
  });

  group('loadSubspaceCapabilities', () {
    late MockClient mockClient;
    late MockMatrixService mockMatrixService;
    late MockSpaceAccessService mockAccess;

    setUp(() {
      mockClient = MockClient();
      mockMatrixService = MockMatrixService();
      mockAccess = MockSpaceAccessService();
      when(mockMatrixService.client).thenReturn(mockClient);
      when(mockMatrixService.spaceAccess).thenReturn(mockAccess);
    });

    test('reports restricted unavailable when server lacks knock support',
        () async {
      when(
        mockAccess.pickRestrictedRoomVersion(
          wantKnock: anyNamed('wantKnock'),
        ),
      ).thenAnswer((_) async => null);

      final caps = await loadSubspaceCapabilities(mockMatrixService);

      expect(caps.restrictedRoomVersion, isNull);
      expect(caps.disabledModes[JoinMode.knockRestricted], isNotNull);
    });

    test('reports restricted available with room version', () async {
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: true))
          .thenAnswer((_) async => '10');
      when(mockAccess.pickRestrictedRoomVersion(wantKnock: false))
          .thenAnswer((_) async => '10');

      final caps = await loadSubspaceCapabilities(mockMatrixService);

      expect(caps.restrictedRoomVersion, '10');
      expect(caps.disabledModes, isEmpty);
    });
  });
}

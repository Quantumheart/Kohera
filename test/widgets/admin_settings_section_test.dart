import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/features/rooms/widgets/admin_settings_section.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<SpaceAccessService>(),
])
import 'admin_settings_section_test.mocks.dart';

void main() {
  late MockRoom mockRoom;
  late MockMatrixService mockMatrix;
  late MockClient mockClient;
  late MockSpaceAccessService mockAccess;
  late SelectionService selection;

  setUp(() {
    mockRoom = MockRoom();
    mockMatrix = MockMatrixService();
    mockClient = MockClient();
    mockAccess = MockSpaceAccessService();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    selection = SelectionService(client: mockClient);
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockMatrix.spaceAccess).thenReturn(mockAccess);
    when(mockMatrix.selection).thenReturn(selection);
    when(mockAccess.getJoinMode(mockRoom)).thenReturn(JoinMode.invite);
    when(mockAccess.allowedSpaceIds(mockRoom)).thenReturn(const []);
    when(mockAccess.needsUpgradeForRestricted(
      mockRoom,
      wantKnock: anyNamed('wantKnock'),
    ),).thenReturn(false);
    when(mockRoom.id).thenReturn('!r:e.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.topic).thenReturn('A topic');
    when(mockRoom.encrypted).thenReturn(false);
    when(mockRoom.canChangeStateEvent(EventTypes.RoomName)).thenReturn(true);
    when(mockRoom.canChangeStateEvent(EventTypes.RoomTopic)).thenReturn(true);
    when(mockRoom.canChangeStateEvent(EventTypes.Encryption)).thenReturn(true);
    when(mockRoom.canChangeStateEvent(EventTypes.RoomJoinRules))
        .thenReturn(false);
    when(mockRoom.canChangePowerLevel).thenReturn(false);
    when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(null);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChangeNotifierProvider<MatrixService>.value(
            value: mockMatrix,
            child: AdminSettingsSection(room: mockRoom),
          ),
        ),
      ),
    );
  }

  group('AdminSettingsSection', () {
    testWidgets('shows room name and topic fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('ADMIN SETTINGS'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Room name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Topic'), findsOneWidget);
    });

    testWidgets('pre-fills name and topic from room', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Room name'),
      );
      expect(nameField.controller?.text, 'Test Room');

      final topicField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Topic'),
      );
      expect(topicField.controller?.text, 'A topic');
    });

    testWidgets('saving name calls room.setName', (tester) async {
      when(mockRoom.setName(any)).thenAnswer((_) async => '');

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Clear and type new name
      await tester.enterText(
        find.widgetWithText(TextField, 'Room name'),
        'New Name',
      );

      // Tap the save button (first check icon)
      final saveButtons = find.byIcon(Icons.check_rounded);
      await tester.tap(saveButtons.first);
      await tester.pumpAndSettle();

      verify(mockRoom.setName('New Name')).called(1);
    });

    testWidgets('saving topic calls room.setDescription', (tester) async {
      when(mockRoom.setDescription(any)).thenAnswer((_) async => '');

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Topic'),
        'New topic',
      );

      // Tap the second check icon (topic save)
      final saveButtons = find.byIcon(Icons.check_rounded);
      await tester.tap(saveButtons.at(1));
      await tester.pumpAndSettle();

      verify(mockRoom.setDescription('New topic')).called(1);
    });

    testWidgets('shows enable encryption button for unencrypted room',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Enable encryption'), findsOneWidget);
    });

    testWidgets('hides encryption button for already encrypted room',
        (tester) async {
      when(mockRoom.encrypted).thenReturn(true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Enable encryption'), findsNothing);
    });

    testWidgets('enable encryption shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Enable').last);
      await tester.pumpAndSettle();

      expect(find.text('Enable encryption?'), findsOneWidget);
      expect(find.textContaining('irreversible'), findsOneWidget);
    });

    testWidgets('confirming encryption calls room.enableEncryption',
        (tester) async {
      when(mockRoom.enableEncryption()).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the enable button on the settings section
      await tester.tap(find.widgetWithText(FilledButton, 'Enable').last);
      await tester.pumpAndSettle();

      // Tap the enable button in the confirmation dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Enable').last);
      await tester.pumpAndSettle();

      verify(mockRoom.enableEncryption()).called(1);
    });

    testWidgets('shows error on save failure', (tester) async {
      when(mockRoom.setName(any)).thenThrow(Exception('Server error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room name'),
        'Failing Name',
      );
      await tester.tap(find.byIcon(Icons.check_rounded).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('shows success message after save', (tester) async {
      when(mockRoom.setName(any)).thenAnswer((_) async => '');

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Room name'),
        'Updated Name',
      );
      await tester.tap(find.byIcon(Icons.check_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Room name updated'), findsOneWidget);
    });

    testWidgets('hides name field when lacking permission', (tester) async {
      when(mockRoom.canChangeStateEvent(EventTypes.RoomName)).thenReturn(false);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Room name'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:kohera/features/spaces/widgets/space_reparent_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<SelectionService>(),
  MockSpec<PreferencesService>(),
  MockSpec<SpaceRoomsController>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'room_list_test.mocks.dart';

void main() {
  late MockMatrixService matrix;
  late MockSelectionService selection;
  late MockPreferencesService prefs;
  late MockSpaceRoomsController spaceRooms;
  late MockClient client;

  setUp(() {
    matrix = MockMatrixService();
    selection = MockSelectionService();
    prefs = MockPreferencesService();
    spaceRooms = MockSpaceRoomsController();
    when(spaceRooms.fetchSpaceRooms(any)).thenAnswer((_) async => {});
    client = MockClient();

    when(matrix.client).thenReturn(client);
    when(selection.selectedSpaceIds).thenReturn({});
    when(selection.rooms).thenReturn([]);
    when(selection.spaceTree).thenReturn([]);
    when(selection.spaces).thenReturn([]);
    when(selection.invitedRooms).thenReturn([]);
    when(selection.orphanRooms).thenReturn([]);
    when(prefs.collapsedSpaceSections).thenReturn({});
    when(client.getRoomById(any)).thenReturn(null);
  });

  Widget wrap(Widget child) => MaterialApp(
    home: child,
    builder: (context, child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrix),
        ChangeNotifierProvider<SelectionService>.value(value: selection),
        ChangeNotifierProvider<PreferencesService>.value(value: prefs),
        ChangeNotifierProvider<SpaceRoomsController>.value(
          value: spaceRooms,
        ),
        ChangeNotifierProvider<SpaceReparentController>(
          create: (_) => SpaceReparentController(),
        ),
      ],
      child: child,
    ),
  );

  group('RoomList', () {
    testWidgets('renders empty state with Chats title', (tester) async {
      await tester.pumpWidget(wrap(const RoomList()));
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('No rooms yet'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    });

    testWidgets('opens and closes search', (tester) async {
      await tester.pumpWidget(wrap(const RoomList()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('renders space empty loading state', (tester) async {
      const spaceId = '!space:example.com';
      final space = MockRoom();
      when(space.id).thenReturn(spaceId);
      when(space.isSpace).thenReturn(true);
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(selection.roomsForSpace(spaceId)).thenReturn([]);
      when(spaceRooms.isCached(spaceId)).thenReturn(true);
      when(
        spaceRooms.getRoomState(spaceId),
      ).thenReturn(const SpaceRoomsState(loading: true));

      await tester.pumpWidget(wrap(const RoomList()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Loading rooms…'), findsOneWidget);
    });

    testWidgets('renders space empty error state', (tester) async {
      const spaceId = '!space:example.com';
      final space = MockRoom();
      when(space.id).thenReturn(spaceId);
      when(space.getLocalizedDisplayname()).thenReturn('Test Space');
      when(space.isSpace).thenReturn(true);
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(selection.roomsForSpace(spaceId)).thenReturn([]);
      when(spaceRooms.isCached(spaceId)).thenReturn(true);
      when(
        spaceRooms.getRoomState(spaceId),
      ).thenReturn(const SpaceRoomsState(error: 'failed'));

      await tester.pumpWidget(wrap(const RoomList()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Could not load rooms'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders space empty forbidden state', (tester) async {
      const spaceId = '!space:example.com';
      final space = MockRoom();
      when(space.id).thenReturn(spaceId);
      when(space.getLocalizedDisplayname()).thenReturn('Secret Space');
      when(space.isSpace).thenReturn(true);
      when(selection.selectedSpaceIds).thenReturn({spaceId});
      when(client.getRoomById(spaceId)).thenReturn(space);
      when(selection.roomsForSpace(spaceId)).thenReturn([]);
      when(spaceRooms.isCached(spaceId)).thenReturn(true);
      when(
        spaceRooms.getRoomState(spaceId),
      ).thenReturn(const SpaceRoomsState(previewForbidden: true));

      await tester.pumpWidget(wrap(const RoomList()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("You're in the Secret Space space"), findsOneWidget);
      expect(find.text('Browse rooms'), findsOneWidget);
    });

    testWidgets('opens FAB speed dial', (tester) async {
      await tester.pumpWidget(wrap(const RoomList()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();

      expect(find.text('New Room'), findsOneWidget);
      expect(find.text('New Direct Message'), findsOneWidget);
      expect(find.text('Join with address'), findsOneWidget);
    });
  });
}

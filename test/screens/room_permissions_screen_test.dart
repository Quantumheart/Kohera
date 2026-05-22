import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/screens/room_permissions_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
])
import 'room_permissions_screen_test.mocks.dart';

const _roomId = '!room:example.com';

// Minimal power_levels content used by most tests.
Map<String, Object?> _plContent({
  int invite = 0,
  int eventsDefault = 0,
  int redact = 50,
  int kick = 50,
  int ban = 50,
  int stateDefault = 50,
  Map<String, Object?>? events,
  Map<String, Object?>? notifications,
}) =>
    {
      'invite': invite,
      'events_default': eventsDefault,
      'redact': redact,
      'kick': kick,
      'ban': ban,
      'state_default': stateDefault,
      if (events != null) 'events': events,
      if (notifications != null) 'notifications': notifications,
    };

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockRoom;
  late MockEvent mockPlEvent;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockRoom = MockRoom();
    mockPlEvent = MockEvent();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);
    when(mockRoom.id).thenReturn(_roomId);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.canChangePowerLevel).thenReturn(false);
    when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(mockPlEvent);
    when(mockPlEvent.content).thenReturn(_plContent());
    when(mockClient.setRoomStateWithKey(any, any, any, any))
        .thenAnswer((_) async => r'$eventId');
  });

  Widget buildScreen() => ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrixService,
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const RoomPermissionsScreen(roomId: _roomId),
        ),
      );

  group('RoomPermissionsScreen', () {
    testWidgets('shows WHO CAN… section header', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('WHO CAN…'), findsOneWidget);
    });

    testWidgets('shows all 9 permission rows', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Invite people'), findsOneWidget);
      expect(find.text('Send messages'), findsOneWidget);
      expect(find.text('Change room name & topic'), findsOneWidget);
      expect(find.text('Change room avatar'), findsOneWidget);
      expect(find.text('Pin messages'), findsOneWidget);
      expect(find.text("Redact others' messages"), findsOneWidget);
      expect(find.text('Mention @room'), findsOneWidget);
      expect(find.text('Kick members'), findsOneWidget);
      expect(find.text('Ban members'), findsOneWidget);
    });

    testWidgets('dropdowns are disabled when canChangePowerLevel is false',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(false);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final dropdowns = tester.widgetList<DropdownButton<int>>(
        find.byType(DropdownButton<int>),
      );
      for (final d in dropdowns) {
        expect(d.onChanged, isNull,
            reason: 'All dropdowns should be disabled',);
      }
    });

    testWidgets('dropdowns are enabled when canChangePowerLevel is true',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final dropdowns = tester.widgetList<DropdownButton<int>>(
        find.byType(DropdownButton<int>),
      );
      for (final d in dropdowns) {
        expect(d.onChanged, isNotNull,
            reason: 'All dropdowns should be enabled',);
      }
    });

    testWidgets('shows correct current value for invite row', (tester) async {
      when(mockPlEvent.content).thenReturn(_plContent(invite: 50));

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // The invite row's dropdown should display 'Moderators+'.
      // Each row renders a DropdownButton, find the one adjacent to the label.
      final inviteRow = find.ancestor(
        of: find.text('Invite people'),
        matching: find.byType(Padding),
      ).first;
      expect(
        find.descendant(of: inviteRow, matching: find.text('Moderators+')),
        findsOneWidget,
      );
    });

    testWidgets('shows Custom label for non-preset value', (tester) async {
      when(mockPlEvent.content).thenReturn(_plContent(kick: 75));

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Custom (75)'), findsOneWidget);
    });

    testWidgets('no power_levels event shows defaults without crashing',
        (tester) async {
      when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(null);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('WHO CAN…'), findsOneWidget);
    });

    testWidgets('changing invite dropdown calls setRoomStateWithKey',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Open the Invite people dropdown (currently 'Everyone' = 0).
      final inviteRow = find.ancestor(
        of: find.text('Invite people'),
        matching: find.byType(Padding),
      ).first;
      await tester.tap(
        find.descendant(of: inviteRow, matching: find.byType(DropdownButton<int>)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Moderators+').last);
      await tester.pumpAndSettle();

      final captured = verify(
        mockClient.setRoomStateWithKey(
          _roomId,
          EventTypes.RoomPowerLevels,
          '',
          captureAny,
        ),
      ).captured.single as Map<String, Object?>;

      expect(captured['invite'], 50);
    });

    testWidgets(
        'changing name & topic row sets both RoomName and RoomTopic events',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final nameRow = find.ancestor(
        of: find.text('Change room name & topic'),
        matching: find.byType(Padding),
      ).first;
      await tester.tap(
        find.descendant(of: nameRow, matching: find.byType(DropdownButton<int>)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Admins only').last);
      await tester.pumpAndSettle();

      final captured = verify(
        mockClient.setRoomStateWithKey(any, any, any, captureAny),
      ).captured.single as Map<String, Object?>;

      final events = captured['events']! as Map<String, Object?>;
      expect(events[EventTypes.RoomName], 100);
      expect(events[EventTypes.RoomTopic], 100);
    });

    testWidgets('room not found shows fallback message', (tester) async {
      when(mockClient.getRoomById(_roomId)).thenReturn(null);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Room not found'), findsOneWidget);
    });
  });
}

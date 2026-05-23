import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/screens/room_permissions_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<User>(),
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
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);
    when(mockRoom.id).thenReturn(_roomId);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.canChangePowerLevel).thenReturn(false);
    when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(mockPlEvent);
    when(mockPlEvent.content).thenReturn(_plContent());
    when(mockRoom.getParticipants()).thenReturn([]);
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

  group('Roles section', () {
    MockUser makeUser(String id, int powerLevel) {
      final u = MockUser();
      when(u.id).thenReturn(id);
      when(mockRoom.getPowerLevelByUserId(id)).thenReturn(powerLevel);
      return u;
    }

    testWidgets('shows ROLES section header', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('ROLES'), findsOneWidget);
    });

    testWidgets('shows Admin, Moderator and Member role cards', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Moderator'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
    });

    testWidgets('shows correct member counts for each role', (tester) async {
      // Pre-compute users before calling when() — makeUser itself calls when()
      // internally, and nesting when() inside thenReturn([...]) corrupts
      // mockito's stub-setup state.
      final alice = makeUser('@alice:example.com', 100);
      final bob = makeUser('@bob:example.com', 50);
      final carol = makeUser('@carol:example.com', 50);
      final dave = makeUser('@dave:example.com', 0);
      when(mockRoom.getParticipants()).thenReturn([alice, bob, carol, dave]);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Admin=1, Member=1 → two "1 member" labels; Moderators=2.
      expect(find.text('1 member'), findsNWidgets(2));
      expect(find.text('2 members'), findsOneWidget);
    });

    testWidgets('tapping a role card expands capabilities list', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('What a moderator can do:'), findsNothing);

      await tester.tap(find.text('Moderator'));
      await tester.pumpAndSettle();

      expect(find.text('What a moderator can do:'), findsOneWidget);
    });

    testWidgets('tapping again collapses the capabilities list', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Member'));
      await tester.pumpAndSettle();
      expect(find.text('What a member can do:'), findsOneWidget);

      await tester.tap(find.text('Member'));
      await tester.pumpAndSettle();
      expect(find.text('What a member can do:'), findsNothing);
    });

    testWidgets('Member card shows Send messages capability with default levels',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Member'));
      await tester.pumpAndSettle();

      // Scope to the expanded card — "Send messages" also appears in WHO CAN….
      final memberCard = find.ancestor(
        of: find.text('What a member can do:'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: memberCard, matching: find.text('Send messages')),
        findsOneWidget,
      );
    });

    testWidgets(
        'Member card does not show kick capability when kick requires level 50',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Member'));
      await tester.pumpAndSettle();

      // Scope to the expanded card — "Kick members" also appears in WHO CAN….
      final memberCard = find.ancestor(
        of: find.text('What a member can do:'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: memberCard, matching: find.text('Kick members')),
        findsNothing,
      );
    });

    testWidgets('plCapabilities returns all capabilities for admin level',
        (tester) async {
      final content = _plContent();
      final caps = plCapabilities(100, content);

      expect(caps, contains('Send messages'));
      expect(caps, contains('Invite people'));
      expect(caps, contains('Kick members'));
      expect(caps, contains('Ban & unban members'));
      expect(caps, contains("Redact others' messages"));
    });

    testWidgets(
        'plCapabilities excludes kick/ban for member when thresholds are 50',
        (tester) async {
      final content = _plContent();
      final memberCaps = plCapabilities(0, content);
      final modCaps = plCapabilities(50, content);

      expect(memberCaps, isNot(contains('Kick members')));
      expect(memberCaps, isNot(contains('Ban & unban members')));
      expect(modCaps, contains('Kick members'));
      expect(modCaps, contains('Ban & unban members'));
    });
  });
}

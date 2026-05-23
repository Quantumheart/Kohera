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

  group('Danger zone section', () {
    // Scrolls the ListView far enough to bring the Danger Zone into view.
    Future<void> scrollToDangerZone(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
    }

    testWidgets('hidden when user has no change permissions', (tester) async {
      // Default setUp: canChangePowerLevel=false, canChangeJoinRules=false,
      // canChangeStateEvent(Encryption)=false → section returns SizedBox.shrink.
      // No need to scroll — hidden section produces no widget at any offset.
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      expect(find.text('DANGER ZONE'), findsNothing);
    });

    testWidgets('shows DANGER ZONE header when canChangePowerLevel is true',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      expect(find.text('DANGER ZONE'), findsOneWidget);
    });

    testWidgets(
        'shows Who can change permissions row when canChangePowerLevel is true',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      expect(find.text('Who can change permissions'), findsOneWidget);
    });

    testWidgets('shows Who can join row when canChangeJoinRules is true',
        (tester) async {
      when(mockRoom.canChangeJoinRules).thenReturn(true);
      // joinRules is a non-abstract getter; stub via noSuchMethod recording.
      when(mockRoom.joinRules).thenReturn(JoinRules.invite);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      expect(find.text('Who can join'), findsOneWidget);
      expect(find.text('Invite-only'), findsOneWidget);
    });

    testWidgets(
        'shows Enable encryption button when not encrypted and allowed',
        (tester) async {
      when(mockRoom.encrypted).thenReturn(false);
      when(mockRoom.canChangeStateEvent(EventTypes.Encryption))
          .thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      expect(find.text('Enable encryption'), findsOneWidget);
      expect(find.text('Enable'), findsOneWidget);
    });

    testWidgets(
        'Enable encryption button not shown when room is already encrypted',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockRoom.encrypted).thenReturn(true);
      when(mockRoom.canChangeStateEvent(EventTypes.Encryption))
          .thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      // Section is visible (canChangePowerLevel=true) but encrypt row hidden.
      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('Enable encryption'), findsNothing);
    });

    testWidgets(
        'changing permissions level calls setRoomStateWithKey after confirm',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockRoom.getPowerLevelByUserId(any)).thenReturn(100);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToDangerZone(tester);

      // Default perm level is state_default=50 → 'Moderators+'.
      // Open the Who can change permissions dropdown.
      final dangerRow = find.ancestor(
        of: find.text('Who can change permissions'),
        matching: find.byType(Padding),
      ).first;
      await tester.tap(
        find.descendant(
            of: dangerRow, matching: find.byType(DropdownButton<int>),),
      );
      await tester.pumpAndSettle();

      // Select 'Admins only' (level 100).
      await tester.tap(find.text('Admins only').last);
      await tester.pumpAndSettle();

      // Confirm dialog appears — tap Confirm.
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final captured = verify(
        mockClient.setRoomStateWithKey(
          _roomId,
          EventTypes.RoomPowerLevels,
          '',
          captureAny,
        ),
      ).captured.single as Map<String, Object?>;

      final events = captured['events']! as Map<String, Object?>;
      expect(events[EventTypes.RoomPowerLevels], 100);
    });
  });
  group('Advanced section', () {
    Future<void> scrollToAdvanced(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }

    Future<void> expandAdvanced(WidgetTester tester) async {
      await scrollToAdvanced(tester);
      await tester.tap(find.text('ADVANCED'));
      await tester.pumpAndSettle();
    }

    testWidgets('ADVANCED header is hidden when canChangePowerLevel is false',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(false);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToAdvanced(tester);

      expect(find.text('ADVANCED'), findsNothing);
    });

    testWidgets('ADVANCED header is visible when canChangePowerLevel is true',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToAdvanced(tester);

      expect(find.text('ADVANCED'), findsOneWidget);
    });

    testWidgets('section is collapsed by default', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await scrollToAdvanced(tester);

      expect(find.text('users_default'), findsNothing);
    });

    testWidgets('tapping ADVANCED expands scalar fields', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      expect(find.text('users_default'), findsOneWidget);
      expect(find.text('state_default'), findsOneWidget);
      expect(find.text('events_default'), findsOneWidget);
    });

    testWidgets('scalar fields show values from power_levels content',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockPlEvent.content).thenReturn(
        _plContent(stateDefault: 75, eventsDefault: 25),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      // state_default label field should have '75' as its value.
      final stateField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'state_default'),
      );
      expect(stateField.controller?.text, '75');

      final eventsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'events_default'),
      );
      expect(eventsField.controller?.text, '25');
    });

    testWidgets('Apply button is disabled when nothing has changed',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(applyButton.onPressed, isNull);
    });

    testWidgets('editing a scalar field enables Apply button', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'users_default'),
        '10',
      );
      await tester.pump();

      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(applyButton.onPressed, isNotNull);
    });

    testWidgets('Apply calls setRoomStateWithKey with updated scalar',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'users_default'),
        '10',
      );
      await tester.pump();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      final captured = verify(
        mockClient.setRoomStateWithKey(
          _roomId,
          EventTypes.RoomPowerLevels,
          '',
          captureAny,
        ),
      ).captured.single as Map<String, Object?>;

      expect(captured['users_default'], 10);
    });

    testWidgets('non-integer input shows validation error and disables Apply',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'state_default'),
        'abc',
      );
      await tester.pump();

      expect(find.text('Scalar values must be integers.'), findsOneWidget);
      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(applyButton.onPressed, isNull);
    });

    testWidgets('Reset restores fields to server values', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'users_default'),
        '99',
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      final usersField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'users_default'),
      );
      expect(usersField.controller?.text, '0');
    });

    testWidgets('existing per-event rows are rendered when expanded',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockPlEvent.content).thenReturn(
        _plContent(events: {'m.room.encryption': 100}),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      expect(find.text('m.room.encryption'), findsOneWidget);
    });

    testWidgets('Add button appends a new event row', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      expect(find.widgetWithText(TextField, 'Event type'), findsNothing);

      // Scroll to the Add icon (inside TextButton.icon) before tapping.
      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Event type'), findsOneWidget);
    });

    testWidgets('Remove button deletes the event row', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockPlEvent.content).thenReturn(
        _plContent(events: {'m.room.encryption': 100}),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      expect(find.text('m.room.encryption'), findsOneWidget);

      // Use the icon widget directly — byTooltip resolves to the overlay render
      // object which can be off-screen even after ensureVisible.
      await tester.ensureVisible(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('m.room.encryption'), findsNothing);
    });

    testWidgets('duplicate event type shows validation error', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockPlEvent.content).thenReturn(
        _plContent(events: {'m.room.encryption': 100}),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      // Add a second row.
      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // enterText works off-screen (uses semantics, not hit-test).
      final typeFields = find.widgetWithText(TextField, 'Event type');
      await tester.enterText(typeFields.last, 'm.room.encryption');
      await tester.pump();

      expect(
        find.textContaining('Duplicate event type'),
        findsOneWidget,
      );
    });

    testWidgets('empty event type shows validation error and disables Apply',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // New row starts with an empty type — validation fires immediately.
      expect(find.text('Event type cannot be empty.'), findsOneWidget);
      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(applyButton.onPressed, isNull);
    });

    testWidgets(
        'Apply with removed row sends events map without the deleted key',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockPlEvent.content).thenReturn(
        _plContent(events: {'m.room.encryption': 100, 'm.room.name': 50}),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      // Remove whichever row appears first (m.room.encryption).
      await tester.ensureVisible(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      final captured = verify(
        mockClient.setRoomStateWithKey(any, any, any, captureAny),
      ).captured.single as Map<String, Object?>;

      final events = captured['events']! as Map<String, Object?>;
      expect(events.length, 1);
      expect(events.containsKey('m.room.encryption'), isFalse);
      expect(events['m.room.name'], 50);
    });

    testWidgets('Apply with added row includes new key in payload',
        (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final typeFields = find.widgetWithText(TextField, 'Event type');
      await tester.enterText(typeFields.last, 'm.room.history_visibility');

      final levelFields = find.widgetWithText(TextField, 'Level');
      await tester.enterText(levelFields.last, '100');
      await tester.pump();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      final captured = verify(
        mockClient.setRoomStateWithKey(any, any, any, captureAny),
      ).captured.single as Map<String, Object?>;

      final events = captured['events']! as Map<String, Object?>;
      expect(events['m.room.history_visibility'], 100);
    });

    testWidgets('server error is shown after failed Apply', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => throw MatrixException.fromJson({
                'errcode': 'M_FORBIDDEN',
                'error': 'You do not have permission',
              },),);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'users_default'),
        '10',
      );
      await tester.pump();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.textContaining('You do not have permission'), findsOneWidget);
    });

    testWidgets('second tap on ADVANCED collapses the section', (tester) async {
      when(mockRoom.canChangePowerLevel).thenReturn(true);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      expect(find.text('users_default'), findsOneWidget);

      await tester.tap(find.text('ADVANCED'));
      await tester.pumpAndSettle();

      expect(find.text('users_default'), findsNothing);
    });
  });
}

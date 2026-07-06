import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/models/kohera_room_permissions.dart';
import 'package:kohera/features/rooms/screens/room_permissions_host.dart';
import 'package:kohera/features/rooms/screens/room_permissions_screen.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
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

// ── Helpers ──────────────────────────────────────────────────

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
      'events': ?events,
      'notifications': ?notifications,
    };

KoheraRoomPermissions _perms({
  Map<String, Object?>? powerLevelsContent,
  List<KoheraRoomMember> participants = const [],
  bool canChangePowerLevels = false,
  bool canChangeJoinRules = false,
  bool canEnableEncryption = false,
  bool isEncrypted = false,
  KoheraJoinRule? joinRule,
  int myPowerLevel = 0,
}) =>
    KoheraRoomPermissions(
      roomId: _roomId,
      displayName: 'Test Room',
      topic: 'A topic',
      canEditName: false,
      canEditTopic: false,
      canEditAvatar: false,
      canInvite: false,
      canChangeJoinRules: canChangeJoinRules,
      canChangePowerLevels: canChangePowerLevels,
      canEnableEncryption: canEnableEncryption,
      joinRule: joinRule,
      isEncrypted: isEncrypted,
      powerLevelsContent: powerLevelsContent ?? _plContent(),
      participants: participants,
      myPowerLevel: myPowerLevel,
    );

/// Records callback invocations for verification.
class _CallbackRecorder {
  KoheraJoinRule? lastJoinRule;
  bool enableEncryptionCalled = false;
  PowerLevelPatch? lastPatch;
  Map<String, Object?>? lastContent;

  Future<void> onSetJoinRules(KoheraJoinRule rule) async {
    lastJoinRule = rule;
  }

  Future<void> onEnableEncryption() async {
    enableEncryptionCalled = true;
  }

  Future<void> onUpdatePowerLevel(PowerLevelPatch patch) async {
    lastPatch = patch;
  }

  Future<void> onApplyPowerLevelsContent(Map<String, Object?> content) async {
    lastContent = content;
  }
}

Widget _wrapScreen(
  KoheraRoomPermissions perms,
  _CallbackRecorder recorder, {
  bool asHost = false,
  MockMatrixService? matrixService,
}) {
  if (asHost) {
    return ChangeNotifierProvider<MatrixService>.value(
      value: matrixService!,
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const RoomPermissionsHost(roomId: _roomId),
      ),
    );
  }

  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: RoomPermissionsScreen(
      permissions: perms,
      onSetJoinRules: recorder.onSetJoinRules,
      onEnableEncryption: recorder.onEnableEncryption,
      onUpdatePowerLevel: recorder.onUpdatePowerLevel,
      onApplyPowerLevelsContent: recorder.onApplyPowerLevelsContent,
    ),
  );
}

// ── Scroll helpers ──────────────────────────────────────────

Future<void> _scrollToDangerZone(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -2000));
  await tester.pumpAndSettle();
}

Future<void> _scrollToAdvanced(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -3000));
  await tester.pumpAndSettle();
}

// ── RoomPermissionsScreen tests (SDK-free widget) ────────────

void main() {
  group('RoomPermissionsScreen — Who Can section', () {
    testWidgets('shows WHO CAN… section header', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
      await tester.pumpAndSettle();

      expect(find.text('WHO CAN…'), findsOneWidget);
    });

    testWidgets('shows all 9 permission rows', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
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

    testWidgets('dropdowns are disabled when canChangePowerLevels is false',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(), recorder),
      );
      await tester.pumpAndSettle();

      final dropdowns = find.byType(DropdownButton<int>);
      for (final db in tester.widgetList<DropdownButton<int>>(dropdowns)) {
        expect(db.onChanged, isNull);
      }
    });

    testWidgets('dropdowns are enabled when canChangePowerLevels is true',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(canChangePowerLevels: true), recorder),
      );
      await tester.pumpAndSettle();

      final dropdowns = find.byType(DropdownButton<int>);
      for (final db in tester.widgetList<DropdownButton<int>>(dropdowns)) {
        expect(db.onChanged, isNotNull);
      }
    });

    testWidgets('shows Custom label for non-preset value', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(powerLevelsContent: _plContent(invite: 25)),
          recorder,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom (25)'), findsOneWidget);
    });

    testWidgets('no power_levels event shows defaults without crashing',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(powerLevelsContent: {}), recorder),
      );
      await tester.pumpAndSettle();

      // Should show defaults (Everyone = 0)
      expect(find.text('Everyone'), findsWidgets);
    });

    testWidgets('changing invite dropdown calls onUpdatePowerLevel',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(
            canChangePowerLevels: true,
            powerLevelsContent: _plContent(),
          ),
          recorder,
        ),
      );
      await tester.pumpAndSettle();

      // Find the Invite people row dropdown and tap it
      final inviteRow = find.ancestor(
        of: find.text('Invite people'),
        matching: find.byType(Padding),
      );
      await tester.tap(
        find.descendant(
          of: inviteRow,
          matching: find.byType(DropdownButton<int>),
        ),
      );
      await tester.pumpAndSettle();

      // Select 'Moderators+' (50)
      await tester.tap(find.text('Moderators+').last);
      await tester.pumpAndSettle();

      expect(recorder.lastPatch, isNotNull);
      expect(recorder.lastPatch!.invite, 50);
    });
  });

  group('RoomPermissionsScreen — Roles section', () {
    testWidgets('shows ROLES section header', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
      await tester.pumpAndSettle();

      expect(find.text('ROLES'), findsOneWidget);
    });

    testWidgets('shows Admin, Moderator and Member role cards', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Moderator'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
    });

    testWidgets('shows correct member counts for each role', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(
            participants: [
              const KoheraRoomMember(
                userId: '@admin:e.com',
                displayname: 'Admin',
                membership: 'join',
                powerLevel: 100,
              ),
              const KoheraRoomMember(
                userId: '@mod:e.com',
                displayname: 'Mod',
                membership: 'join',
                powerLevel: 50,
              ),
              const KoheraRoomMember(
                userId: '@user:e.com',
                displayname: 'User',
                membership: 'join',
                powerLevel: 0,
              ),
            ],
          ),
          recorder,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 member'), findsNWidgets(3));
    });

    testWidgets('tapping a role card expands capabilities list',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();

      expect(find.textContaining('What a admin can do:'), findsOneWidget);
    });

    testWidgets('tapping again collapses the capabilities list',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('What a admin can do:'), findsOneWidget);

      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('What a admin can do:'), findsNothing);
    });
  });

  group('plCapabilities', () {
    test('returns all capabilities for admin level', () {
      final caps = plCapabilities(100, _plContent());
      expect(caps, contains('Send messages'));
      expect(caps, contains('Invite people'));
      expect(caps, contains('Mention @room'));
      expect(caps, contains("Redact others' messages"));
      expect(caps, contains('Change room name & topic'));
      expect(caps, contains('Change room avatar'));
      expect(caps, contains('Pin messages'));
      expect(caps, contains('Kick members'));
      expect(caps, contains('Ban & unban members'));
      expect(caps, contains('Change permissions'));
    });

    test('returns subset for moderator level', () {
      final caps = plCapabilities(50, _plContent());
      // At level 50 with default settings, moderator can do most things.
      expect(caps, contains('Send messages'));
      expect(caps, contains('Kick members'));
      expect(caps, contains('Ban & unban members'));
      // Cannot ban at level 0
      final caps0 = plCapabilities(0, _plContent());
      expect(caps0, isNot(contains('Ban & unban members')));
      expect(caps0, isNot(contains('Kick members')));
    });

    test('returns minimal for member level with defaults', () {
      final caps = plCapabilities(0, _plContent());
      expect(caps, contains('Send messages'));
      expect(caps, contains('Invite people'));
      expect(caps, isNot(contains('Kick members')));
    });
  });

  group('RoomPermissionsScreen — Danger zone section', () {
    testWidgets('hidden when user has no change permissions', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(),
          recorder,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToDangerZone(tester);

      expect(find.text('DANGER ZONE'), findsNothing);
    });

    testWidgets('shows DANGER ZONE header when canChangePowerLevels is true',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(canChangePowerLevels: true), recorder),
      );
      await tester.pumpAndSettle();
      await _scrollToDangerZone(tester);

      expect(find.text('DANGER ZONE'), findsOneWidget);
    });

    testWidgets('shows Who can join row when canChangeJoinRules is true',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(
            canChangeJoinRules: true,
            joinRule: KoheraJoinRule.invite,
          ),
          recorder,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToDangerZone(tester);

      expect(find.text('Who can join'), findsOneWidget);
    });

    testWidgets(
        'shows Enable encryption button when canEnableEncryption is true',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(canEnableEncryption: true),
          recorder,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToDangerZone(tester);

      expect(find.text('Enable encryption'), findsOneWidget);
    });

    testWidgets('changing join rule calls onSetJoinRules', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(
            canChangeJoinRules: true,
            joinRule: KoheraJoinRule.invite,
          ),
          recorder,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToDangerZone(tester);

      // Tap the join rule dropdown
      await tester.tap(find.byType(DropdownButton<KoheraJoinRule>));
      await tester.pumpAndSettle();

      // Select 'Public'
      await tester.tap(find.text('Public').last);
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(recorder.lastJoinRule, KoheraJoinRule.public);
    });

    testWidgets('enabling encryption calls onEnableEncryption', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(
          _perms(canEnableEncryption: true),
          recorder,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollToDangerZone(tester);

      await tester.tap(
        find.byElementPredicate(
          (el) =>
              el.widget is FilledButton &&
              (el.widget as FilledButton).child is Text &&
              ((el.widget as FilledButton).child! as Text).data == 'Enable',
        ),
      );
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(recorder.enableEncryptionCalled, isTrue);
    });
  });

  group('RoomPermissionsScreen — Advanced section', () {
    testWidgets('ADVANCED header is hidden when canChangePowerLevels is false',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(_wrapScreen(_perms(), recorder));
      await tester.pumpAndSettle();
      await _scrollToAdvanced(tester);

      expect(find.text('ADVANCED'), findsNothing);
    });

    testWidgets('ADVANCED header is visible when canChangePowerLevels is true',
        (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(canChangePowerLevels: true), recorder),
      );
      await tester.pumpAndSettle();
      await _scrollToAdvanced(tester);

      expect(find.text('ADVANCED'), findsOneWidget);
    });

    testWidgets('section is collapsed by default', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(canChangePowerLevels: true), recorder),
      );
      await tester.pumpAndSettle();
      await _scrollToAdvanced(tester);

      expect(find.text('Scalar defaults'), findsNothing);
    });

    testWidgets('tapping ADVANCED expands scalar fields', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(canChangePowerLevels: true), recorder),
      );
      await tester.pumpAndSettle();
      await _scrollToAdvanced(tester);

      await tester.tap(find.text('ADVANCED'));
      await tester.pumpAndSettle();

      expect(find.text('Scalar defaults'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'users_default'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'state_default'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'events_default'), findsOneWidget);
    });

    testWidgets('Apply button is disabled when not dirty', (tester) async {
      final recorder = _CallbackRecorder();
      await tester.pumpWidget(
        _wrapScreen(_perms(canChangePowerLevels: true), recorder),
      );
      await tester.pumpAndSettle();
      await _scrollToAdvanced(tester);

      await tester.tap(find.text('ADVANCED'));
      await tester.pumpAndSettle();

      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(applyButton.onPressed, isNull);
    });
  });

  group('RoomPermissionsHost — boundary widget', () {
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
      when(mockClient.userID).thenReturn('@me:e.com');
      when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);
      when(mockRoom.id).thenReturn(_roomId);
      when(mockRoom.client).thenReturn(mockClient);
      when(mockRoom.canChangePowerLevel).thenReturn(false);
      when(mockRoom.canChangeJoinRules).thenReturn(false);
      when(mockRoom.encrypted).thenReturn(true);
      when(mockRoom.joinRules).thenReturn(JoinRules.invite);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
      when(mockRoom.topic).thenReturn('Topic');
      when(mockRoom.getState(EventTypes.RoomPowerLevels))
          .thenReturn(mockPlEvent);
      when(mockPlEvent.content).thenReturn(_plContent());
      when(mockRoom.getParticipants()).thenReturn([]);
      when(mockRoom.getPowerLevelByUserId(any)).thenReturn(PowerLevel(0));
      when(mockRoom.canChangeStateEvent(EventTypes.RoomName)).thenReturn(false);
      when(mockRoom.canChangeStateEvent(EventTypes.RoomTopic))
          .thenReturn(false);
      when(mockRoom.canChangeStateEvent(EventTypes.RoomAvatar))
          .thenReturn(false);
      when(mockRoom.canChangeStateEvent(EventTypes.Encryption))
          .thenReturn(false);
    });

    testWidgets('room not found shows fallback message', (tester) async {
      when(mockClient.getRoomById(_roomId)).thenReturn(null);

      await tester.pumpWidget(
        _wrapScreen(
          _perms(),
          _CallbackRecorder(),
          asHost: true,
          matrixService: mockMatrixService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Room not found'), findsOneWidget);
    });

    testWidgets('renders screen with permissions from room', (tester) async {
      await tester.pumpWidget(
        _wrapScreen(
          _perms(),
          _CallbackRecorder(),
          asHost: true,
          matrixService: mockMatrixService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Permissions'), findsOneWidget);
      expect(find.text('ROLES'), findsOneWidget);
      expect(find.text('WHO CAN…'), findsOneWidget);
    });
  });
}

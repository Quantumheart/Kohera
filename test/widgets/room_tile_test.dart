import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/rooms/widgets/room_tile.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:kohera/shared/models/kohera_user_summary.dart';
@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<CallService>(),
])
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/presence_dot.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_tile_test.mocks.dart';


class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size}) async => null;
}

KoheraRoomSummary _summary({
  String roomId = '!room:example.com',
  String displayname = 'Test Room',
  bool isDirectChat = false,
  String? dmUserId,
  int notificationCount = 0,
  int highlightCount = 0,
  List<String> typingDisplayNames = const [],
  String lastEventPreview = 'Hello',
  DateTime? lastEventTimestamp,
  bool lastEventIsThreadReply = false,
  bool isFavourite = false,
  bool isSpace = false,
  List<String> pinnedEventIds = const [],
  int spaceChildCount = 0,
}) => KoheraRoomSummary(
  roomId: roomId,
  displayname: displayname,
  isDirectChat: isDirectChat,
  dmUserId: dmUserId,
  isEncrypted: false,
  isSpace: isSpace,
  notificationCount: notificationCount,
  highlightCount: highlightCount,
  typingDisplayNames: typingDisplayNames,
  pinnedEventIds: pinnedEventIds,
  spaceChildCount: spaceChildCount,
  isFavourite: isFavourite,
  lastEventPreview: lastEventPreview,
  lastEventBody: lastEventPreview,
  lastEventTimestamp: lastEventTimestamp,
  lastEventIsThreadReply: lastEventIsThreadReply,
);

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockClient mockClient;
  late MockCallService mockCallService;
  late PreferencesService prefs;
  String? lastNavigatedRoom;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockClient = MockClient();
    mockCallService = MockCallService();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockMatrix.avatarResolver).thenReturn(const _NullAvatarResolver());
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockClient.onPresenceChanged).thenReturn(CachedStreamController<CachedPresence>());
    when(mockMatrix.presence).thenReturn(PresenceService(client: mockClient));

    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.notificationCount).thenReturn(0);
    when(mockRoom.highlightCount).thenReturn(0);
    when(mockRoom.membership).thenReturn(Membership.join);
    when(mockRoom.lastEvent).thenReturn(null);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.directChatMatrixID).thenReturn(null);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.typingUsers).thenReturn([]);

    when(mockCallService.roomHasActiveCall(any)).thenReturn(false);
    when(mockCallService.isCallingAvailable).thenReturn(true);
  });

  Widget buildTestWidget({
    KoheraRoomSummary? summary,
    bool isSelected = false,
    Set<String> memberships = const {},
    KoheraUserSummary? Function(String userId)? userLookup,
  }) {
    lastNavigatedRoom = null;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: RoomTile(
        summary: summary ?? _summary(),
              isSelected: isSelected,
              memberships: memberships,
              hasContextMenu: false,
              userLookup: userLookup,
            ),
          ),
          routes: [
            GoRoute(
              path: RouteSegments.room,
              name: Routes.room,
              builder: (context, state) {
                lastNavigatedRoom = state.pathParameters[RouteParams.roomId];
                return Scaffold(
                  body: Text('Room ${state.pathParameters[RouteParams.roomId]}'),
                );
              },
            ),
          ],
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
        ChangeNotifierProvider<CallService>.value(value: mockCallService),
        ChangeNotifierProvider<PreferencesService>.value(value: prefs),
      ],
      child: MaterialApp.router(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      routerConfig: router,),
    );
  }

  // ── Unread badge ──────────────────────────────────────────

  group('Unread badge', () {
    testWidgets('no badge at 0 unread', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows count when unread > 0', (tester) async {
      when(mockRoom.notificationCount).thenReturn(5);
      await tester.pumpWidget(buildTestWidget(summary: _summary(notificationCount: 5)));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows 99+ when count exceeds 99', (tester) async {
      when(mockRoom.notificationCount).thenReturn(150);
      await tester.pumpWidget(buildTestWidget(summary: _summary(notificationCount: 150)));
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
    });
  });

  // ── Last message preview ──────────────────────────────────

  group('Last message preview', () {
    testWidgets('shows "No messages yet" when lastEvent is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'No messages yet')));
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('shows text body', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'Hello world')));
      await tester.pumpAndSettle();

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('shows image emoji for image message', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: '📷 Image')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Image'), findsOneWidget);
    });

    testWidgets('shows video emoji for video message', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: '🎬 Video')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Video'), findsOneWidget);
    });

    testWidgets('shows file emoji for file message', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: '📎 File')));
      await tester.pumpAndSettle();

      expect(find.textContaining('File'), findsOneWidget);
    });

    testWidgets('shows audio emoji for audio message', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: '🎵 Audio')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Audio'), findsOneWidget);
    });

    testWidgets('shows "Unable to decrypt" for BadEncrypted', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: '🔒 Unable to decrypt')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to decrypt'), findsOneWidget);
    });

    testWidgets('shows "You deleted this message" for own redacted',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'You deleted this message')));
      await tester.pumpAndSettle();

      expect(find.text('You deleted this message'), findsOneWidget);
    });

    testWidgets('shows "This message was deleted" for other redacted',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'This message was deleted')));
      await tester.pumpAndSettle();

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('shows "Call in progress" for call invite', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'Call in progress')));
      await tester.pumpAndSettle();

      expect(find.text('Call in progress'), findsOneWidget);
    });

    testWidgets('shows "Call ended" for hangup', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'Call ended')));
      await tester.pumpAndSettle();

      expect(find.text('Call ended'), findsOneWidget);
    });

    testWidgets('shows "Missed call" for hangup with invite_timeout',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventPreview: 'Missed call')));
      await tester.pumpAndSettle();

      expect(find.text('Missed call'), findsOneWidget);
    });
  });

  // ── Typing indicator ──────────────────────────────────────

  group('Typing indicator', () {
    testWidgets('shows typing text when enabled and users typing',
        (tester) async {
      SharedPreferences.setMockInitialValues({'typing_indicators': true});
      final sp = await SharedPreferences.getInstance();
      prefs = PreferencesService(prefs: sp);

      await tester.pumpWidget(buildTestWidget(summary: _summary(typingDisplayNames: ['Bob'])));
      await tester.pumpAndSettle();

      expect(find.text('Bob is typing'), findsOneWidget);
    });

    testWidgets('shows last message when typing disabled', (tester) async {
      SharedPreferences.setMockInitialValues({'typing_indicators': false});
      final sp = await SharedPreferences.getInstance();
      prefs = PreferencesService(prefs: sp);

      await tester.pumpWidget(buildTestWidget(summary: _summary(typingDisplayNames: ['Bob'], lastEventPreview: 'Last msg')));
      await tester.pumpAndSettle();

      expect(find.text('Bob is typing'), findsNothing);
      expect(find.text('Last msg'), findsOneWidget);
    });
  });

  // ── Call indicator ────────────────────────────────────────

  group('Call indicator', () {
    testWidgets('shows green call icon when room has active call',
        (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(KIcons.headsetMicRounded), findsAtLeast(1));
    });

    testWidgets('hides green call indicator when no active call', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final greenIcons = tester.widgetList<Icon>(find.byIcon(KIcons.headsetMicRounded))
          .where((icon) => icon.color == Colors.green);
      expect(greenIcons, isEmpty);
    });
  });

  // ── Selection ─────────────────────────────────────────────

  group('Selection', () {
    testWidgets('applies primaryContainer background when selected',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(isSelected: true));
      await tester.pumpAndSettle();

      final material = tester.widgetList<Material>(find.byType(Material))
          .where((m) => m.color != null && m.color != Colors.transparent)
          .firstOrNull;
      expect(material, isNotNull);
    });
  });

  // ── Navigation ────────────────────────────────────────────

  group('Navigation', () {
    testWidgets('tap navigates to room route', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Room'));
      await tester.pumpAndSettle();

      expect(lastNavigatedRoom, '!room:example.com');
    });
  });

  // ── Timestamp ─────────────────────────────────────────────

  group('Timestamp', () {
    testWidgets('shows "now" for recent events', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventTimestamp: DateTime.now())));
      await tester.pumpAndSettle();

      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('shows minutes for events within the hour', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventTimestamp: DateTime.now().subtract(const Duration(minutes: 15)))));
      await tester.pumpAndSettle();

      expect(find.text('15m'), findsOneWidget);
    });

    testWidgets('shows hours for events within the day', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventTimestamp: DateTime.now().subtract(const Duration(hours: 3)))));
      await tester.pumpAndSettle();

      expect(find.text('3h'), findsOneWidget);
    });

    testWidgets('shows days for events within the week', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventTimestamp: DateTime.now().subtract(const Duration(days: 2)))));
      await tester.pumpAndSettle();

      expect(find.text('2d'), findsOneWidget);
    });

    testWidgets('shows DD/MM for events older than a week', (tester) async {
      await tester.pumpWidget(buildTestWidget(summary: _summary(lastEventTimestamp: DateTime(2025, 3, 15))));
      await tester.pumpAndSettle();

      expect(find.text('15/03'), findsOneWidget);
    });
  });

  // ── Active call controls ──────────────────────────────────

  group('Active call controls', () {
    testWidgets('shows Join button when room has active call and user is not connected',
        (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(KoheraCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);
    });

    testWidgets('shows Leave button and elapsed time when user connected to this call',
        (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn('!room:example.com');
      when(mockCallService.callState).thenReturn(KoheraCallState.connected);
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(seconds: 42));
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('00:42'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('shows call icon button when no active call', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsNothing);
      expect(find.text('Leave'), findsNothing);
      expect(find.byIcon(KIcons.headsetMicRounded), findsAtLeast(1));
    });
  });

  // ── Call participant list ─────────────────────────────────

  group('Call participant list', () {
    late MockUser mockAlice;
    late MockUser mockBob;

    setUp(() {
      mockAlice = MockUser();
      when(mockAlice.displayName).thenReturn('Alice');
      when(mockAlice.id).thenReturn('@alice:example.com');

      mockBob = MockUser();
      when(mockBob.displayName).thenReturn('Bob');
      when(mockBob.id).thenReturn('@bob:example.com');
    });

    testWidgets('shows participant avatars with tooltips when call is active', (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(KoheraCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({'@alice:example.com', '@bob:example.com'});

      await tester.pumpWidget(buildTestWidget(userLookup: (userId) {
        if (userId == '@alice:example.com') return const KoheraUserSummary(userId: '@alice:example.com', displayname: 'Alice');
        if (userId == '@bob:example.com') return const KoheraUserSummary(userId: '@bob:example.com', displayname: 'Bob');
        return null;
      },),);
      await tester.pumpAndSettle();

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip))
          .where((t) => t.message == 'Alice' || t.message == 'Bob');
      expect(tooltips.length, 2);
    });

    testWidgets('shows You tooltip first when user is connected', (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn('!room:example.com');
      when(mockCallService.callState).thenReturn(KoheraCallState.connected);
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(seconds: 10));
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({'@alice:example.com', '@me:example.com'});

      await tester.pumpWidget(buildTestWidget(userLookup: (userId) {
        if (userId == '@alice:example.com') return const KoheraUserSummary(userId: '@alice:example.com', displayname: 'Alice');
        if (userId == '@me:example.com') return const KoheraUserSummary(userId: '@me:example.com', displayname: 'Me');
        return null;
      },),);
      await tester.pump();

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final callTooltips = tooltips.where((t) => t.message == 'You' || t.message == 'Alice').toList();
      expect(callTooltips.length, 2);
      expect(callTooltips.first.message, 'You');
    });

    testWidgets('shows overflow indicator when more than 8 participants', (tester) async {
      final userIds = <String>{};
      for (var i = 0; i < 10; i++) {
        userIds.add('@user$i:example.com');
      }

      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(KoheraCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn(userIds);

      await tester.pumpWidget(buildTestWidget(userLookup: (userId) {
        final match = RegExp(r'@user(\d+):').firstMatch(userId);
        if (match != null) {
          return KoheraUserSummary(userId: userId, displayname: 'User ${match.group(1)}');
        }
        return null;
      },),);
      await tester.pumpAndSettle();

      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('expands on tap and shows collapse icon', (tester) async {
      final userIds = <String>{};
      for (var i = 0; i < 10; i++) {
        userIds.add('@user$i:example.com');
      }

      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(KoheraCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn(userIds);

      await tester.pumpWidget(buildTestWidget(userLookup: (userId) {
        final match = RegExp(r'@user(\d+):').firstMatch(userId);
        if (match != null) {
          return KoheraUserSummary(userId: userId, displayname: 'User ${match.group(1)}');
        }
        return null;
      },),);
      await tester.pumpAndSettle();

      await tester.tap(find.text('+2'));
      await tester.pumpAndSettle();

      expect(find.byIcon(KIcons.expandLess), findsOneWidget);
      expect(find.text('+2'), findsNothing);
      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip))
          .where((t) => t.message == 'User 9');
      expect(tooltips.length, 1);
    });
  });

  // ── Presence dot (DM only) ─────────────────────────────────

  group('Presence dot', () {
    late CachedStreamController<CachedPresence> presenceController;

    void enablePresence() {
      presenceController = CachedStreamController<CachedPresence>();
      when(mockClient.onPresenceChanged).thenReturn(presenceController);
      when(mockMatrix.presence)
          .thenReturn(PresenceService(client: mockClient));
    }

    Finder dot() => find.descendant(
          of: find.byType(PresenceDot),
          matching: find.byType(Container),
        );

    testWidgets('shows counterpart dot for a direct chat', (tester) async {
      enablePresence();
      when(mockRoom.isDirectChat).thenReturn(true);
      when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

      await tester.pumpWidget(buildTestWidget(summary: _summary(isDirectChat: true, dmUserId: '@bob:example.com')));
      await tester.pumpAndSettle();

      presenceController.add(
        CachedPresence(PresenceType.online, null, null, true, '@bob:example.com'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PresenceDot), findsOneWidget);
      expect(dot(), findsOneWidget);
    });

    testWidgets('shows no presence overlay for a group room', (tester) async {
      enablePresence();
      when(mockRoom.isDirectChat).thenReturn(false);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(PresenceDot), findsNothing);
    });

    testWidgets('direct chat with unknown presence shows no dot',
        (tester) async {
      enablePresence();
      when(mockRoom.isDirectChat).thenReturn(true);
      when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

      await tester.pumpWidget(buildTestWidget(summary: _summary(isDirectChat: true, dmUserId: '@bob:example.com')));
      await tester.pumpAndSettle();

      expect(find.byType(PresenceDot), findsOneWidget);
      expect(dot(), findsNothing);
    });
  });
}

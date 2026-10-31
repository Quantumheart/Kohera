import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kohera/core/routing/app_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/account_session.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/draft_store.dart';
import 'package:kohera/core/services/github_releases_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/state/key_backup_setup_state.dart';
import 'package:kohera/core/state/selection_controller.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/core/theme/theme_presets.dart';
import 'package:kohera/data/repositories/auth_repository.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/outbox_repository.dart';
import 'package:kohera/data/repositories/push_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';
import 'package:kohera/data/repositories/sticker_pack_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/features/auth/screens/login_screen.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart' show SpaceChild;
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'helpers/mocks.dart';
import 'helpers/test_app.dart';

const Map<String, ({Size logical, double dpr})> _viewports = {
  'narrow': (logical: Size(390, 844), dpr: 3),
  'wide': (logical: Size(1280, 800), dpr: 1),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  loginScreenshots();
  homeShellScreenshots();
  chatScreenshots();
}

void _stubClientBasics(
  MockClient mockClient,
  CachedStreamController<SyncUpdate> syncController,
) {
  when(mockClient.rooms).thenReturn([]);
  when(mockClient.onSync).thenReturn(syncController);
  when(mockClient.onLoginStateChanged)
      .thenReturn(CachedStreamController<LoginState>());
  when(mockClient.onUiaRequest)
      .thenReturn(CachedStreamController<UiaRequest<dynamic>>());
  when(mockClient.onPresenceChanged)
      .thenReturn(CachedStreamController<CachedPresence>());
}

// ── Login screenshots ───────────────────────────────────────────────────────

void loginScreenshots() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late PreferencesService preferences;
  late CachedStreamController<SyncUpdate> syncController;
  late ValueNotifier<bool> navigatedToHome;
  final boundaryKey = GlobalKey();

  setUp(() async {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    AppConfig.setInstance(AppConfig.testInstance());
    syncController = CachedStreamController<SyncUpdate>();
    _stubClientBasics(mockClient, syncController);
    matrixService = MatrixService(
      accountSession: AccountSession(
        matrixClientService: MatrixClientService(mockClient),
        storage: mockStorage,
        clientName: 'screenshot',
      ),
      storage: mockStorage,
      clientName: 'screenshot',
    );
    clientManager = ClientManager(
      storage: mockStorage,
      serviceFactory: FixedServiceFactory(matrixService),
    );
    preferences = PreferencesService();
    await preferences.init();
    navigatedToHome = ValueNotifier(false);
  });

  for (final entry in _viewports.entries) {
    final name = entry.key;
    final vp = entry.value;

    testWidgets('login screen — $name', (tester) async {
      stubPasswordServer(mockClient);
      stubSuccessfulLogin(mockClient, syncController);

      await _fixViewport(tester, vp);
      await tester.pumpWidget(
        ChangeNotifierProvider<PreferencesService>.value(
          value: preferences,
          child: RepaintBoundary(
            key: boundaryKey,
            child: buildTestApp(
              matrixService: matrixService,
              clientManager: clientManager,
              navigatedToHome: navigatedToHome,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await _capture(tester, boundaryKey, 'login_$name');
    });
  }
}

// ── Real HomeShell screenshots ──────────────────────────────────────────────
// Pumps the real buildRouter + the full provider tree from main.dart against a
// mocked Client whose `rooms` are seeded (incl. one space with children for the
// space drawer). Captures the Chats tab (RoomList) at narrow + wide, in light
// and dark theme. No network, no credentials.

const String _me = '@me:example.com';
const String _spaceId = '!kohera-devs:example.com';

void homeShellScreenshots() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late PreferencesService preferences;
  late CachedStreamController<SyncUpdate> syncController;
  late List<Room> rooms;
  final boundaryKey = GlobalKey();

  setUp(() async {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    AppConfig.setInstance(AppConfig.testInstance());
    syncController = CachedStreamController<SyncUpdate>();
    stubLoggedInClient(mockClient, syncController);
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.userID).thenReturn(_me);
    when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));

    rooms = _seedRooms(mockClient);
    when(mockClient.rooms).thenReturn(rooms);
    when(mockClient.getRoomById(any)).thenAnswer(
      (i) => rooms.firstWhere(
        (r) => r.id == i.positionalArguments[0] as String,
        orElse: () => rooms.first,
      ),
    );

    matrixService = MatrixService(
      accountSession: AccountSession(
        matrixClientService: MatrixClientService(mockClient),
        storage: mockStorage,
        clientName: 'screenshot',
      ),
      storage: mockStorage,
      clientName: 'screenshot',
    )..isLoggedInForTest = true;

    clientManager = ClientManager(
      storage: mockStorage,
      serviceFactory: FixedServiceFactory(matrixService),
    );
    await clientManager.addService(matrixService);

    preferences = PreferencesService();
    await preferences.init();
    await preferences.setLastMobileTab(MobileTab.chats);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    final themeName = theme == ThemeMode.light ? 'light' : 'dark';
    for (final entry in _viewports.entries) {
      final vpName = entry.key;
      final vp = entry.value;

      testWidgets('home — $vpName — $themeName', (tester) async {
        final router =
            buildRouter(clientManager, refreshListenable: matrixService);
        await _fixViewport(tester, vp);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: _homeShellApp(
              matrixService: matrixService,
              clientManager: clientManager,
              preferences: preferences,
              mockClient: mockClient,
              themeMode: theme,
              router: router,
            ),
          ),
        );
        // Let the router settle + InboxController's first fetch settle.
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(RoomList), findsWidgets);

        await _capture(tester, boundaryKey, 'home_${vpName}_$themeName');
      });
    }
  }
}

Widget _homeShellApp({
  required MatrixService matrixService,
  required ClientManager clientManager,
  required PreferencesService preferences,
  required MockClient mockClient,
  required ThemeMode themeMode,
  required GoRouter router,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ClientManager>.value(value: clientManager),
      ChangeNotifierProvider<PreferencesService>.value(value: preferences),
      ChangeNotifierProvider(create: (_) => MediaPlaybackService()),
      Provider(
        create: (_) => GitHubReleasesService(),
        dispose: (_, s) => s.dispose(),
      ),
      ChangeNotifierProvider<MatrixService>.value(value: matrixService),
      ChangeNotifierProvider<SpaceTreeRepository>.value(
        value: matrixService.spaceTree,
      ),
      ChangeNotifierProvider<SelectionController>.value(
        value: matrixService.selectionController,
      ),
      Provider<SpaceDiscoveryDataSource>(
        create: (_) => LiveSpaceDiscoveryDataSource(mockClient),
      ),
      ChangeNotifierProvider<SpaceRoomsController>(
        create: (ctx) => SpaceRoomsController(
          dataSource: ctx.read<SpaceDiscoveryDataSource>(),
          client: mockClient,
        )..listenToSync(),
      ),
      ChangeNotifierProvider<KeyBackupSetupState>.value(
        value: matrixService.keyBackupSetupState,
      ),
      ChangeNotifierProvider<OutboxRepository>.value(
        value: matrixService.session.outboxRepository,
      ),
      ChangeNotifierProvider<StickerPackRepository>.value(
        value: matrixService.session.stickerPackRepository,
      ),
      ChangeNotifierProvider<DraftStore>(
        create: (_) => DraftStore(clientName: matrixService.clientName),
      ),
      ChangeNotifierProvider<PushRepository>(
        create: (ctx) => PushRepository(
          clientService: ctx.read<MatrixService>().session.matrixClientService,
        ),
      ),
      ChangeNotifierProxyProvider<PushRepository, InboxController>(
        create: (ctx) => InboxController(
          pushRepository: ctx.read<PushRepository>(),
        ),
        update: (_, pushRepo, previous) {
          if (previous == null) {
            return InboxController(pushRepository: pushRepo);
          }
          previous.updateRepository(pushRepo);
          return previous;
        },
      ),
      ChangeNotifierProvider<CallService>(
        create: (_) => CallService(client: mockClient),
      ),
      ChangeNotifierProvider<RoomRepository>(
        create: (ctx) => RoomRepository(
          clientService: ctx.read<MatrixService>().session.matrixClientService,
        ),
      ),
      ChangeNotifierProvider<UserRepository>.value(
        value: matrixService.session.userRepository,
      ),
      ChangeNotifierProvider<MessageRepository>.value(
        value: matrixService.session.messageRepository,
      ),
      ChangeNotifierProvider<AuthRepository>(
        create: (ctx) => AuthRepository(
          clientService: ctx.read<MatrixService>().session.matrixClientService,
          auth: ctx.read<MatrixService>().session.auth,
          setupState:
              ctx.read<MatrixService>().session.keyBackupSetupState,
        ),
      ),
      ChangeNotifierProvider<KeyBackupRepository>.value(
        value: matrixService.keyBackupRepository,
      ),
      ChangeNotifierProvider<MediaRepository>(
        create: (ctx) => MediaRepository(
          avatarResolver:
              ctx.read<MatrixService>().session.avatarResolver,
          mediaResolver: ctx.read<MatrixService>().session.mediaResolver,
        ),
      ),
      ChangeNotifierProvider<SpaceRepository>(
        create: (ctx) => SpaceRepository(
          clientService: ctx.read<MatrixService>().session.matrixClientService,
        ),
      ),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: KoheraTheme.light(preset: getPreset(preferences.themePreset)),
      darkTheme: KoheraTheme.dark(preset: getPreset(preferences.themePreset)),
      themeMode: themeMode,
      routerConfig: router,
    ),
  );
}

// ── Room fixtures ───────────────────────────────────────────────────────────

List<Room> _seedRooms(MockClient client) {
  final space = _stubRoom(
    client,
    id: _spaceId,
    name: 'Kohera Devs',
    isSpace: true,
    children: const ['!proj-alpha:example.com', '!proj-beta:example.com'],
  );
  final alpha = _stubRoom(
    client,
    id: '!proj-alpha:example.com',
    name: 'Project Alpha',
    lastBody: 'Kenji: shipped the build ✅',
    lastSender: 'Kenji',
    unread: 1,
  );
  final beta = _stubRoom(
    client,
    id: '!proj-beta:example.com',
    name: 'Project Beta',
    lastBody: 'standup notes posted',
    lastSender: 'Sora',
  );
  final design = _stubRoom(
    client,
    id: '!design:example.com',
    name: 'Design Sync',
    lastBody: 'sending the new icons now 🎨',
    lastSender: 'Sora',
    unread: 3,
    highlight: 1,
    encrypted: true,
    favourite: true,
  );
  final alice = _stubRoom(
    client,
    id: '!alice:example.com',
    name: 'Alice',
    lastBody: 'see you tomorrow!',
    lastSender: 'Alice',
    encrypted: true,
    directChatUserId: '@alice:example.com',
  );
  final family = _stubRoom(
    client,
    id: '!family:example.com',
    name: 'Family',
    lastBody: 'Mom: dinner at 7',
    lastSender: 'Mom',
    unread: 5,
  );
  final announce = _stubRoom(
    client,
    id: '!announce:example.com',
    name: 'Announcements',
    lastBody: 'v2.3 released',
    lastSender: 'Announcements',
    pushRuleState: PushRuleState.mentionsOnly,
  );
  final quiet = _stubRoom(
    client,
    id: '!quiet:example.com',
    name: 'Quiet Room',
  );
  return [space, alpha, beta, design, alice, family, announce, quiet];
}

MockRoom _stubRoom(
  MockClient client, {
  required String id,
  required String name,
  String? lastBody,
  String? lastSender,
  int unread = 0,
  int highlight = 0,
  bool encrypted = false,
  bool favourite = false,
  bool isSpace = false,
  String? directChatUserId,
  PushRuleState pushRuleState = PushRuleState.notify,
  List<String> children = const [],
}) {
  final room = MockRoom();
  when(room.id).thenReturn(id);
  when(room.getLocalizedDisplayname()).thenReturn(name);
  when(room.client).thenReturn(client);
  when(room.topic).thenReturn('');
  when(room.avatar).thenReturn(null);
  when(room.canonicalAlias).thenReturn('');
  when(room.encrypted).thenReturn(encrypted);
  when(room.isDirectChat).thenReturn(directChatUserId != null);
  when(room.directChatMatrixID).thenReturn(directChatUserId);
  when(room.isSpace).thenReturn(isSpace);
  when(room.isFavourite).thenReturn(favourite);
  when(room.membership).thenReturn(Membership.join);
  when(room.notificationCount).thenReturn(unread);
  when(room.highlightCount).thenReturn(highlight);
  when(room.typingUsers).thenReturn(<User>[]);
  when(room.pinnedEventIds).thenReturn(<String>[]);
  when(room.pushRuleState).thenReturn(pushRuleState);
  when(room.canChangeStateEvent(any)).thenReturn(false);
  when(room.canChangePowerLevel).thenReturn(false);
  when(room.canKick).thenReturn(false);
  when(room.canBan).thenReturn(false);
  when(room.getPowerLevelByUserId(any)).thenReturn(PowerLevel(0));
  when(room.summary).thenReturn(
    RoomSummary.fromJson({'m.joined_member_count': 4}),
  );
  when(room.requestParticipants(any)).thenAnswer((_) async => []);
  when(room.unsafeGetUserFromMemoryOrFallback(any)).thenAnswer(
    (i) => User(
      i.positionalArguments[0] as String,
      room: room,
      displayName: lastSender,
    ),
  );
  when(room.spaceChildren).thenReturn(
    children.map(_spaceChild).toList(),
  );
  if (lastBody != null && lastSender != null) {
    when(room.lastEvent).thenReturn(
      Event(
        type: EventTypes.Message,
        content: {'body': lastBody, 'msgtype': 'm.text'},
        eventId: '\$last:$id',
        senderId: '@${lastSender.toLowerCase()}:example.com',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
  } else {
    when(room.lastEvent).thenReturn(null);
  }
  return room;
}

SpaceChild _spaceChild(String roomId) => SpaceChild.fromState(
      StrippedStateEvent(
        type: EventTypes.SpaceChild,
        content: const <String, Object?>{},
        senderId: _me,
        stateKey: roomId,
      ),
    );

// ── Capture plumbing ────────────────────────────────────────────────────────

Future<void> _fixViewport(
  WidgetTester tester,
  ({Size logical, double dpr}) vp,
) async {
  tester.view.devicePixelRatio = vp.dpr;
  tester.view.physicalSize = vp.logical * vp.dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  // Rasterize the wrapped RepaintBoundary to a PNG and ship the bytes back to
  // the host driver via binding.reportData. The driver writes one file per
  // entry to build/screenshots. This avoids the platform-native
  // captureScreenshot path, which returns stale/identical frames on iOS under
  // `flutter drive`, and works uniformly across web, mobile, and desktop.
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image =
        await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    binding.reportData ??= <String, dynamic>{};
    final shots = binding.reportData!.putIfAbsent(
      'screenshots',
      () => <dynamic>[],
    ) as List<dynamic>;
    shots.add(<String, dynamic>{
      'screenshotName': name,
      'bytesBase64': base64Encode(bytes),
    });
    debugPrint('[Kohera] screenshot captured: $name (${bytes.length} bytes)');
  });
}

// ── Chat screen screenshots ─────────────────────────────────────────────────
// Navigates the real HomeShell to /rooms/!design:example.com so ChatScreen
// renders inside the shell, backed by a seeded MockTimeline of events from
// multiple senders.

const String _chatRoomId = '!design:example.com';

void chatScreenshots() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late PreferencesService preferences;
  late CachedStreamController<SyncUpdate> syncController;
  late MockTimeline timeline;
  final boundaryKey = GlobalKey();

  setUp(() async {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    AppConfig.setInstance(AppConfig.testInstance());
    syncController = CachedStreamController<SyncUpdate>();
    stubLoggedInClient(mockClient, syncController);
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.userID).thenReturn(_me);
    when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
    when(mockClient.onTimelineEvent)
        .thenReturn(CachedStreamController<Event>());
    when(mockClient.onRoomState).thenReturn(
      CachedStreamController<({String roomId, StrippedStateEvent state})>(),
    );
    when(mockClient.ignoredUsers).thenReturn(<String>[]);
    when(mockClient.postReceipt(
      any,
      any,
      any,
      threadId: anyNamed('threadId'),
    )).thenAnswer((_) async {});

    final rooms = _seedRooms(mockClient);
    final chatRoom = rooms.firstWhere((r) => r.id == _chatRoomId) as MockRoom;
    _stubChatRoom(chatRoom);
    timeline = MockTimeline();
    when(timeline.events).thenReturn(_chatEvents(chatRoom));
    when(timeline.canRequestHistory).thenReturn(false);
    when(timeline.allowNewEvent).thenReturn(true);
    when(timeline.isRequestingHistory).thenReturn(false);
    when(timeline.requestHistory(
      historyCount: anyNamed('historyCount'),
      filter: anyNamed('filter'),
    )).thenAnswer((_) async {});
    when(chatRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
        .thenAnswer((_) async => timeline);

    when(mockClient.rooms).thenReturn(rooms);
    when(mockClient.getRoomById(any)).thenAnswer(
      (i) => rooms.firstWhere(
        (r) => r.id == i.positionalArguments[0] as String,
        orElse: () => rooms.first,
      ),
    );

    matrixService = MatrixService(
      accountSession: AccountSession(
        matrixClientService: MatrixClientService(mockClient),
        storage: mockStorage,
        clientName: 'screenshot',
      ),
      storage: mockStorage,
      clientName: 'screenshot',
    )..isLoggedInForTest = true;

    clientManager = ClientManager(
      storage: mockStorage,
      serviceFactory: FixedServiceFactory(matrixService),
    );
    await clientManager.addService(matrixService);

    preferences = PreferencesService();
    await preferences.init();
    await preferences.setLastMobileTab(MobileTab.chats);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    final themeName = theme == ThemeMode.light ? 'light' : 'dark';
    for (final entry in _viewports.entries) {
      final vpName = entry.key;
      final vp = entry.value;

      testWidgets('chat — $vpName — $themeName', (tester) async {
        final router =
            buildRouter(clientManager, refreshListenable: matrixService);
        await _fixViewport(tester, vp);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: _homeShellApp(
              matrixService: matrixService,
              clientManager: clientManager,
              preferences: preferences,
              mockClient: mockClient,
              themeMode: theme,
              router: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        router.goNamed(
          Routes.room,
          pathParameters: {RouteParams.roomId: _chatRoomId},
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(ChatScreen), findsOneWidget);

        await _capture(tester, boundaryKey, 'chat_${vpName}_$themeName');
      });
    }
  }
}

void _stubChatRoom(MockRoom room) {
  when(room.fullyRead).thenReturn('');
  when(room.receiptState).thenReturn(LatestReceiptState.empty());
  when(room.lastEvent).thenReturn(
    Event(
      type: EventTypes.Message,
      content: {'body': 'sending the new icons now', 'msgtype': 'm.text'},
      eventId: r'$last:design',
      senderId: '@sora:example.com',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );
}

List<Event> _chatEvents(MockRoom room) {
  Event ev({
    required String id,
    required String sender,
    required String body,
    DateTime? ts,
  }) =>
      Event(
        type: EventTypes.Message,
        content: {'body': body, 'msgtype': 'm.text'},
        eventId: id,
        senderId: '@${sender.toLowerCase()}:example.com',
        originServerTs: ts ?? DateTime.now(),
        room: room,
      );
  return [
    ev(id: r'$1', sender: 'Sora', body: 'morning everyone'),
    ev(id: r'$2', sender: 'Kenji', body: 'pushed the icon set to the branch'),
    ev(id: r'$3', sender: 'Me', body: 'looks great, reviewing now'),
    ev(id: r'$4', sender: 'Alice', body: 'the pixel borders are sharper'),
    ev(id: r'$5', sender: 'Sora', body: 'sending the new icons now'),
    ev(id: r'$6', sender: 'Kenji', body: 'merged - build is green'),
    ev(id: r'$7', sender: 'Me', body: 'shipping it'),
  ];
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/calling/widgets/voice_banner.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks/matrix_service_mock.mocks.dart';
import 'room_tile_test.mocks.dart';

void main() {
  late MockCallService mockCallService;
  late MockMatrixService mockMatrixService;
  late MockClient mockClient;
  late MockRoom mockRoom;
  late SpaceTreeRepository selectionService;

  setUp(() {
    mockCallService = MockCallService();
    mockMatrixService = MockMatrixService();
    mockClient = MockClient();
    mockRoom = MockRoom();

    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    when(mockMatrixService.matrixClientService).thenReturn(MatrixClientService(mockClient));
    selectionService = SpaceTreeRepository(clientService: MatrixClientService(mockClient));
    when(mockMatrixService.spaceTree).thenReturn(selectionService);

    when(mockCallService.client).thenReturn(mockClient);
    when(mockCallService.callState).thenReturn(KoheraCallState.idle);
    when(mockCallService.activeCallRoomId).thenReturn(null);
  });

  Widget buildTestWidget({String? currentViewingRoomId}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: VoiceBanner(currentViewingRoomId: currentViewingRoomId),
          ),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CallService>.value(value: mockCallService),
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
        ChangeNotifierProvider<RoomRepository>(
          create: (_) => RoomRepository(clientService: mockMatrixService.matrixClientService),
        ),
      ],
      child: MaterialApp.router(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        routerConfig: router,
      ),
    );
  }

  group('VoiceBanner', () {
    testWidgets('hidden when user is not in a call', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('hidden when user is viewing the same room as active call',
        (tester) async {
      when(mockCallService.callState).thenReturn(KoheraCallState.connected);
      when(mockCallService.activeCallRoomId).thenReturn('!room:example.com');

      await tester.pumpWidget(
        buildTestWidget(currentViewingRoomId: '!room:example.com'),
      );
      await tester.pump();

      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('visible when user is in call but viewing different room',
        (tester) async {
      when(mockCallService.callState).thenReturn(KoheraCallState.connected);
      when(mockCallService.activeCallRoomId).thenReturn('!call-room:example.com');
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(minutes: 1, seconds: 30));
      when(mockClient.getRoomById('!call-room:example.com'))
          .thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Call Room');

      await tester.pumpWidget(
        buildTestWidget(currentViewingRoomId: '!other:example.com'),
      );
      await tester.pump();

      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.textContaining('Call Room'), findsOneWidget);
      expect(find.textContaining('01:30'), findsOneWidget);
    });

    testWidgets('wrapped in SafeArea to avoid status-bar overlap',
        (tester) async {
      when(mockCallService.callState).thenReturn(KoheraCallState.connected);
      when(mockCallService.activeCallRoomId).thenReturn('!call-room:example.com');
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(minutes: 1));
      when(mockClient.getRoomById('!call-room:example.com'))
          .thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Call Room');

      await tester.pumpWidget(
        buildTestWidget(currentViewingRoomId: '!other:example.com'),
      );
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byIcon(Icons.headset_mic_rounded),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
    });
  });
}

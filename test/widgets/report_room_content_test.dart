import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/shared/widgets/report_content_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>(), MockSpec<Event>()])
import '../mocks/matrix_service_mock.mocks.dart';
import 'report_room_content_test.mocks.dart';

void main() {
  late MockClient client;
  late MockMatrixService matrix;
  late RoomRepository roomRepo;
  late UserRepository userRepo;

  setUp(() {
    client = MockClient();
    matrix = MockMatrixService();
    when(matrix.client).thenReturn(client);
    when(client.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    roomRepo = RoomRepository(matrix: matrix);
    userRepo = UserRepository(matrix: matrix);
  });

  testWidgets('reports the room lastEvent with the entered reason', (
    tester,
  ) async {
    final room = MockRoom();
    final event = MockEvent();
    when(room.id).thenReturn('!room:server');
    when(event.eventId).thenReturn(r'$event:server');
    when(room.lastEvent).thenReturn(event);
    when(client.getRoomById('!room:server')).thenReturn(room);
    when(
      client.reportEvent(any, any, reason: anyNamed('reason')),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),

        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => reportRoomContent(
                  context,
                  roomRepo,
                  userRepo,
                  '!room:server',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'spam');
    await tester.pump();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    verify(
      client.reportEvent('!room:server', r'$event:server', reason: 'spam'),
    ).called(1);
    expect(find.text('Reported to homeserver'), findsOneWidget);
  });

  testWidgets('surfaces message when room has no last event', (tester) async {
    final room = MockRoom();
    when(room.lastEvent).thenReturn(null);
    when(client.getRoomById('!room:server')).thenReturn(room);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => reportRoomContent(
                  context,
                  roomRepo,
                  userRepo,
                  '!room:server',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No message available to report'), findsOneWidget);
    verifyNever(client.reportEvent(any, any, reason: anyNamed('reason')));
  });
}

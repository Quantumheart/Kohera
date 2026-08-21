import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/data/models/kohera_room_member.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/features/rooms/services/member_sheet_launcher.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<MatrixService>(),
  MockSpec<SelectionService>(),
])
import 'unban_room_member_test.mocks.dart';

void main() {
  KoheraRoomMember bannedMember({
    String userId = '@spam:example.com',
    String displayname = 'Spammer',
  }) => KoheraRoomMember(
    userId: userId,
    displayname: displayname,
    membership: 'ban',
    powerLevel: 0,
  );

  /// Creates a [RoomRepository] wrapping a mock [MatrixService] that returns
  /// [room] for [roomId]. The same [client] is used for both the matrix mock
  /// and the room mock so stubs on [client] are visible through the repo.
  RoomRepository roomRepoWithRoom(MockRoom room, MockClient client) {
    final matrix = MockMatrixService();
    final selection = MockSelectionService();
    final syncCtl = CachedStreamController<SyncUpdate>();
    final roomId = room.id;

    when(matrix.matrixClientService).thenReturn(MatrixClientService(client));
    when(matrix.selection).thenReturn(selection);
    when(client.onSync).thenReturn(syncCtl);
    when(client.getRoomById(roomId)).thenReturn(room);
    when(room.client).thenReturn(client);

    return RoomRepository(clientService: matrix.matrixClientService, selection: matrix.selection);
  }

  testWidgets(
    'unbanRoomMember calls client.unban and surfaces success snackbar',
    (tester) async {
      final room = MockRoom();
      final client = MockClient();
      when(room.id).thenReturn('!room:server');
      when(room.client).thenReturn(client);
      when(
        client.unban(any, any, reason: anyNamed('reason')),
      ).thenAnswer((_) async {});

      final roomRepo = roomRepoWithRoom(room, client);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => unbanRoomMember(
                    context,
                    roomRepo,
                    '!room:server',
                    bannedMember(),
                  ),
                  child: const Text('unban'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('unban'));
      await tester.pumpAndSettle();

      verify(client.unban('!room:server', '@spam:example.com')).called(1);
      expect(find.text('Unbanned Spammer'), findsOneWidget);
    },
  );

  testWidgets('unbanRoomMember forwards reason when provided', (tester) async {
    final room = MockRoom();
    final client = MockClient();
    when(room.id).thenReturn('!room:server');
    when(room.client).thenReturn(client);
    when(
      client.unban(any, any, reason: anyNamed('reason')),
    ).thenAnswer((_) async {});

    final roomRepo = roomRepoWithRoom(room, client);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => unbanRoomMember(
                  context,
                  roomRepo,
                  '!room:server',
                  bannedMember(),
                  reason: 'spamming',
                ),
                child: const Text('unban'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('unban'));
    await tester.pumpAndSettle();

    verify(
      client.unban('!room:server', '@spam:example.com', reason: 'spamming'),
    ).called(1);
  });

  testWidgets('unbanRoomMember surfaces failure snackbar on error', (
    tester,
  ) async {
    final room = MockRoom();
    final client = MockClient();
    when(room.id).thenReturn('!room:server');
    when(room.client).thenReturn(client);
    when(
      client.unban(any, any, reason: anyNamed('reason')),
    ).thenThrow(Exception('Permission denied'));

    final roomRepo = roomRepoWithRoom(room, client);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => unbanRoomMember(
                  context,
                  roomRepo,
                  '!room:server',
                  bannedMember(),
                ),
                child: const Text('unban'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('unban'));
    await tester.pumpAndSettle();

    verify(client.unban('!room:server', '@spam:example.com')).called(1);
    expect(find.textContaining('Failed to unban'), findsOneWidget);
  });
}

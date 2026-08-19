import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/features/rooms/services/room_aliases_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import '../mocks/matrix_service_mock.mocks.dart';
import 'room_aliases_controller_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockRoom;
  late CachedStreamController<SyncUpdate> syncController;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockRoom = MockRoom();
    syncController = CachedStreamController<SyncUpdate>();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockClient.onSync).thenReturn(syncController);
    when(mockClient.getLocalAliases('!room:example.com'))
        .thenAnswer((_) async => const ['#room:example.com']);
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.canonicalAlias).thenReturn('#room:example.com');
    when(mockRoom.canChangeStateEvent(EventTypes.RoomCanonicalAlias))
        .thenReturn(true);

    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
    when(mockMatrixService.avatarResolver)
        .thenReturn(const _NullAvatarResolver());
  });

  Widget buildTestWidget() => MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
          ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoomAliasesController(roomId: '!room:example.com'),
            ),
          ),
        ),
      );

  group('RoomAliasesController', () {
    testWidgets('loads and displays canonical alias', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('ALIASES'), findsOneWidget);
      expect(find.text('#room:example.com'), findsWidgets);
      expect(find.text('Canonical alias'), findsOneWidget);
    });

    testWidgets('create alias calls setRoomAlias with localpart:domain',
        (tester) async {
      when(mockClient.setRoomAlias(any, any)).thenAnswer((_) async {});
      when(mockClient.getLocalAliases('!room:example.com'))
          .thenAnswer((_) async => const ['#new:example.com', '#room:example.com']);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'new');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      verify(mockClient.setRoomAlias('#new:example.com', '!room:example.com'))
          .called(1);
    });

    testWidgets('delete alias calls deleteRoomAlias', (tester) async {
      when(mockClient.deleteRoomAlias(any)).thenAnswer((_) async {});
      when(mockRoom.canonicalAlias).thenReturn('');
      when(mockClient.getLocalAliases('!room:example.com'))
          .thenAnswer((_) async => const ['#room:example.com']);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('1 alias'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(mockClient.deleteRoomAlias('#room:example.com')).called(1);
    });

    testWidgets('deleting the canonical alias clears canonical state',
        (tester) async {
      when(mockClient.deleteRoomAlias(any)).thenAnswer((_) async {});
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => r'$event');
      when(mockClient.getLocalAliases('!room:example.com'))
          .thenAnswer((_) async => const ['#room:example.com']);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('1 alias'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(mockClient.deleteRoomAlias('#room:example.com')).called(1);
      verify(mockClient.setRoomStateWithKey(
        '!room:example.com',
        EventTypes.RoomCanonicalAlias,
        '',
        <String, Object?>{},
      )).called(1);
    });

    testWidgets('set canonical calls room.setCanonicalAlias', (tester) async {
      when(mockRoom.setCanonicalAlias(any)).thenAnswer((_) async {});
      when(mockClient.getLocalAliases('!room:example.com'))
          .thenAnswer((_) async => const ['#a:example.com', '#b:example.com']);
      when(mockRoom.canonicalAlias).thenReturn('#a:example.com');

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('2 aliases'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set as canonical'));
      await tester.pumpAndSettle();

      verify(mockRoom.setCanonicalAlias('#b:example.com')).called(1);
    });

    testWidgets('reload fires on canonical_alias sync event', (tester) async {
      when(mockClient.getLocalAliases('!room:example.com'))
          .thenAnswer((_) async => const ['#room:example.com']);
      when(mockRoom.canonicalAlias).thenReturn('#room:example.com');

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      syncController.add(SyncUpdate(
        nextBatch: 'b',
        rooms: RoomsUpdate(
          join: {
            '!room:example.com': JoinedRoomUpdate(
              state: [
                MatrixEvent.fromJson({
                  'type': 'm.room.canonical_alias',
                  'sender': '@me:example.com',
                  'event_id': r'$ev:example.com',
                  'origin_server_ts': 1,
                  'content': {'alias': '#room:example.com'},
                }),
              ],
            ),
          },
        ),
      ));
      await tester.pumpAndSettle();

      verify(mockClient.getLocalAliases('!room:example.com')).called(2);
    });
  });
}

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxc, {required double size}) async =>
      null;
}

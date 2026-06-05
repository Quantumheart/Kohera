import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/features/chat/widgets/chat_app_bar.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'room_tile_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockClient mockClient;
  late MockCallService mockCallService;
  late CachedStreamController<CachedPresence> presenceController;

  setUp(() {
    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockClient = MockClient();
    mockCallService = MockCallService();
    presenceController = CachedStreamController<CachedPresence>();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.onPresenceChanged).thenReturn(presenceController);
    when(mockMatrix.presence).thenReturn(PresenceService(client: mockClient));

    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Bob');
    when(mockRoom.pinnedEventIds).thenReturn([]);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.summary).thenReturn(RoomSummary.fromJson({
      'm.joined_member_count': 3,
    }),);
    when(mockRoom.isDirectChat).thenReturn(false);
    when(mockRoom.directChatMatrixID).thenReturn(null);

    when(mockCallService.isCallingAvailable).thenReturn(false);
  });

  Widget build() => MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<CallService>.value(value: mockCallService),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: ChatAppBar(room: mockRoom, onSearch: () {}),
          ),
        ),
      );

  testWidgets('group room shows member count subtitle', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('3 members'), findsOneWidget);
  });

  testWidgets('DM shows counterpart presence as subtitle', (tester) async {
    when(mockRoom.isDirectChat).thenReturn(true);
    when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    presenceController.add(
      CachedPresence(PresenceType.online, null, null, true, '@bob:example.com'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('3 members'), findsNothing);
  });

  testWidgets('DM offline shows last-seen when timestamp provided',
      (tester) async {
    when(mockRoom.isDirectChat).thenReturn(true);
    when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    presenceController.add(
      CachedPresence(PresenceType.offline, 7200000, null, false, '@bob:example.com'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline · last seen'), findsOneWidget);
  });

  testWidgets('DM with unknown presence falls back to member count',
      (tester) async {
    when(mockRoom.isDirectChat).thenReturn(true);
    when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('3 members'), findsOneWidget);
  });
}

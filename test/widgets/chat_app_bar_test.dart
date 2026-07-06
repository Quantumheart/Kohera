import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/chat/widgets/chat_app_bar.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'room_tile_test.mocks.dart';


const _nullAvatarResolver = _NullAvatarResolver();

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size}) async => null;
}

KoheraRoomSummary _summary({
  String roomId = '!room:example.com',
  String displayname = 'Bob',
  bool isDirectChat = false,
  String? dmUserId,
  List<String> pinnedEventIds = const [],
  int spaceChildCount = 3,
}) => KoheraRoomSummary(
  roomId: roomId,
  displayname: displayname,
  isDirectChat: isDirectChat,
  dmUserId: dmUserId,
  isEncrypted: false,
  isSpace: false,
  notificationCount: 0,
  highlightCount: 0,
  typingDisplayNames: const [],
  pinnedEventIds: pinnedEventIds,
  spaceChildCount: spaceChildCount,
  isFavourite: false,
  lastEventPreview: 'No messages yet',
  lastEventIsThreadReply: false,
);

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
    when(mockMatrix.avatarResolver).thenReturn(_nullAvatarResolver);

    when(mockRoom.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Bob');
    when(mockRoom.pinnedEventIds).thenReturn([]);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.summary).thenReturn(RoomSummary.fromJson({
      'm.joined_member_count': 3,
    }),);
    when(mockRoom.isDirectChat).thenReturn(false);
    when(mockRoom.participantListComplete).thenReturn(true);
    when(mockRoom.directChatMatrixID).thenReturn(null);

    when(mockCallService.isCallingAvailable).thenReturn(false);
  });

  Widget build({KoheraRoomSummary? summary}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<CallService>.value(value: mockCallService),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: ChatAppBar(summary: summary ?? _summary(), onSearch: () {}),
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

    await tester.pumpWidget(build(
      summary: _summary(isDirectChat: true, dmUserId: '@bob:example.com'),
    ),);
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

    await tester.pumpWidget(build(
      summary: _summary(isDirectChat: true, dmUserId: '@bob:example.com'),
    ),);
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

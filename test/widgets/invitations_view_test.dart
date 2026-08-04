import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/widgets/inbox/invitations_view.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<SelectionService>(),
  MockSpec<MatrixService>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<AvatarResolver>(),
  MockSpec<MediaResolver>(),
])
import 'invitations_view_test.mocks.dart';

KoheraRoomSummary _summary(String id, String name) {
  return KoheraRoomSummary(
    roomId: id,
    displayname: name,
    isDirectChat: false,
    isEncrypted: false,
    isSpace: false,
    notificationCount: 0,
    highlightCount: 0,
    typingDisplayNames: const [],
    pinnedEventIds: const [],
    spaceChildCount: 0,
    isFavourite: false,
    lastEventPreview: '',
    lastEventIsThreadReply: false,
  );
}

void main() {
  late MockSelectionService mockSelection;
  late MockMatrixService mockMatrix;
  late MockClient mockClient;

  setUp(() {
    mockSelection = MockSelectionService();
    mockMatrix = MockMatrixService();
    mockClient = MockClient();
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.getRoomById(any)).thenReturn(null);
    when(mockMatrix.avatarResolver).thenReturn(MockAvatarResolver());
    when(mockMatrix.mediaResolver).thenReturn(MockMediaResolver());
  });

  Widget wrap() {
    return MaterialApp(
      home: Scaffold(
        body: InvitationsView(
          cs: ThemeData().colorScheme,
          tt: ThemeData().textTheme,
        ),
      ),
      builder: (context, child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<SelectionService>.value(value: mockSelection),
        ],
        child: child,
      ),
    );
  }

  group('InvitationsView', () {
    testWidgets('shows empty state when no invitations', (tester) async {
      when(mockSelection.invitedRooms).thenReturn([]);
      when(mockSelection.invitedSpaces).thenReturn([]);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text(InboxText.noPendingInvitations), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
    });

    testWidgets('shows room invitations with section header', (tester) async {
      final room = MockRoom();
      when(room.id).thenReturn('!room1:example.com');
      when(mockSelection.invitedRooms).thenReturn([room]);
      when(mockSelection.invitedSpaces).thenReturn([]);
      when(mockSelection.summaryFor(room))
          .thenReturn(_summary('!room1:example.com', 'My Room'));
      when(mockSelection.inviterDisplayName(room)).thenReturn('Alice');

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text(InboxText.sectionRooms), findsOneWidget);
      expect(find.text('My Room'), findsOneWidget);
    });

    testWidgets('shows space invitations with section header', (tester) async {
      final space = MockRoom();
      when(space.id).thenReturn('!space1:example.com');
      when(mockSelection.invitedRooms).thenReturn([]);
      when(mockSelection.invitedSpaces).thenReturn([space]);
      when(mockSelection.summaryFor(space))
          .thenReturn(_summary('!space1:example.com', 'My Space'));
      when(mockSelection.inviterDisplayName(space)).thenReturn('Bob');

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text(InboxText.sectionSpaces), findsOneWidget);
      expect(find.text('My Space'), findsOneWidget);
    });

    testWidgets('shows both spaces and rooms with headers', (tester) async {
      final space = MockRoom();
      when(space.id).thenReturn('!space1:example.com');
      final room = MockRoom();
      when(room.id).thenReturn('!room1:example.com');

      when(mockSelection.invitedRooms).thenReturn([room]);
      when(mockSelection.invitedSpaces).thenReturn([space]);
      when(mockSelection.summaryFor(space))
          .thenReturn(_summary('!space1:example.com', 'My Space'));
      when(mockSelection.summaryFor(room))
          .thenReturn(_summary('!room1:example.com', 'My Room'));
      when(mockSelection.inviterDisplayName(space)).thenReturn('Bob');
      when(mockSelection.inviterDisplayName(room)).thenReturn('Alice');

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text(InboxText.sectionSpaces), findsOneWidget);
      expect(find.text(InboxText.sectionRooms), findsOneWidget);
      expect(find.text('My Space'), findsOneWidget);
      expect(find.text('My Room'), findsOneWidget);
    });

    testWidgets('uses ListView when invitations present', (tester) async {
      final room = MockRoom();
      when(room.id).thenReturn('!room1:example.com');
      when(mockSelection.invitedRooms).thenReturn([room]);
      when(mockSelection.invitedSpaces).thenReturn([]);
      when(mockSelection.summaryFor(room))
          .thenReturn(_summary('!room1:example.com', 'My Room'));
      when(mockSelection.inviterDisplayName(room)).thenReturn('Alice');

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
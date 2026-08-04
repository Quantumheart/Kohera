import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/calling/services/call_service.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:kohera/features/chat/services/message_indexer_service.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/model.dart' show ResultCategories;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';


@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
  MockSpec<MessageIndexerService>(),
  MockSpec<AvatarResolver>(),
])
import 'chat_search_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockTimeline mockTimeline;
  late MockMessageIndexerService mockIndexer;
  late MockAvatarResolver mockAvatarResolver;
  late PreferencesService prefsService;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockTimeline = MockTimeline();
    mockIndexer = MockMessageIndexerService();
    mockAvatarResolver = MockAvatarResolver();
    prefsService = PreferencesService();

    when(mockClient.onSync).thenReturn(CachedStreamController());
    when(mockClient.rooms).thenReturn([]);
    selectionService = SelectionService(client: mockClient);

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockMatrix.selection).thenReturn(selectionService);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.receiptState).thenReturn(LatestReceiptState.empty());
    when(mockRoom.summary).thenReturn(
      RoomSummary.fromJson({'m.joined_member_count': 3}),
    );
    when(mockTimeline.events).thenReturn([]);
    when(mockTimeline.canRequestHistory).thenReturn(false);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.getTimeline(eventContextId: anyNamed('eventContextId'), onUpdate: anyNamed('onUpdate')))
        .thenAnswer((_) async => mockTimeline);
    when(mockMatrix.messageIndexer).thenReturn(mockIndexer);
    when(mockMatrix.avatarResolver).thenReturn(mockAvatarResolver);
    when(mockIndexer.isAvailable).thenReturn(false);
    when(mockRoom.encrypted).thenReturn(false);
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ChangeNotifierProvider(create: (ctx) => CallService(client: ctx.read<MatrixService>().client)),
        ChangeNotifierProvider<PreferencesService>.value(value: prefsService),
        ChangeNotifierProvider(create: (ctx) => StickerPackService(client: ctx.read<MatrixService>().client)),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const ChatScreen(roomId: '!room:example.com'),
      ),
    );
  }

  group('ChatScreen search', () {
    testWidgets('shows search icon in app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('tapping search icon shows search app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Search text field should appear.
      expect(find.widgetWithText(TextField, ''), findsWidgets);
      // Back arrow should be present.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      // The original room title should be gone.
      expect(find.text('Test Room'), findsNothing);
      // Hint text should show.
      expect(find.text('Search messages…'), findsOneWidget);
    });

    testWidgets('shows minimum character hint when query too short',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type less than 3 characters.
      await tester.enterText(find.byType(TextField).last, 'a');
      await tester.pumpAndSettle();

      expect(
        find.text('Type at least 2 characters to search'),
        findsOneWidget,
      );
    });

    testWidgets('close button clears search and restores app bar',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Tap back to close.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Room name should be back.
      expect(find.text('Test Room'), findsOneWidget);
      // Search hint should be gone.
      expect(find.text('Search messages…'), findsNothing);
    });

    testWidgets('shows empty state when no results found', (tester) async {
      when(mockClient.search(any, nextBatch: anyNamed('nextBatch')))
          .thenAnswer((_) async => SearchResults(searchCategories: ResultCategories()));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type a query.
      await tester.enterText(find.byType(TextField).last, 'xyz123');
      await tester.pump(const Duration(milliseconds: 600)); // debounce
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No messages found'),
        findsOneWidget,
      );
    });

    testWidgets('shows error state when search fails', (tester) async {
      when(mockClient.search(any, nextBatch: anyNamed('nextBatch')))
          .thenThrow(Exception('Server error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type a query.
      await tester.enterText(find.byType(TextField).last, 'hello world');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Search failed. Please try again.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('shows loading indicator while searching', (tester) async {
      final completer = Completer<SearchResults>();
      when(mockClient.search(any, nextBatch: anyNamed('nextBatch')))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type a query.
      await tester.enterText(find.byType(TextField).last, 'hello');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(); // Trigger the search.

      expect(find.byType(KoheraLoader), findsOneWidget);

      // Complete the future to avoid pending timers.
      completer.complete(SearchResults(searchCategories: ResultCategories()));
      await tester.pumpAndSettle();
    });
  });
}

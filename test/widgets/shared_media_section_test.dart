import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/features/rooms/services/shared_media_loader.dart';
import 'package:kohera/features/rooms/widgets/shared_media_section.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<Client>(),
  MockSpec<User>(),
])
import 'shared_media_section_test.mocks.dart';

typedef _SearchResult = ({
  List<Event> events,
  String? nextBatch,
  DateTime? searchedUntil
});

_SearchResult _result({List<Event> events = const [], String? nextBatch}) =>
    (events: events, nextBatch: nextBatch, searchedUntil: null);

MockEvent _makeEvent(
  String messageType, {
  String body = 'file.dat',
  Map<String, Object?>? info,
  String eventId = r'$evt1',
}) {
  final event = MockEvent();
  final sender = MockUser();
  final room = MockRoom();
  final client = MockClient();

  when(event.messageType).thenReturn(messageType);
  when(event.type).thenReturn(EventTypes.Message);
  when(event.body).thenReturn(body);
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn('@alice:example.com');
  when(event.originServerTs).thenReturn(DateTime(2026, 1, 1, 12));
  when(event.senderFromMemoryOrFallback).thenReturn(sender);
  when(event.room).thenReturn(room);
  when(event.status).thenReturn(EventStatus.synced);
  when(event.isAttachmentEncrypted).thenReturn(false);
  when(event.attachmentMxcUrl).thenReturn(null);
  when(room.client).thenReturn(client);
  when(client.homeserver).thenReturn(Uri.parse('https://example.com'));
  when(client.accessToken).thenReturn('token');
  when(sender.calcDisplayname()).thenReturn('Alice');
  when(sender.avatarUrl).thenReturn(null);
  when(sender.displayName).thenReturn('Alice');

  final content = <String, Object?>{
    'msgtype': messageType,
    'body': body,
    'info': info ?? <String, Object?>{},
  };
  when(event.content).thenReturn(content);

  // Stub getAttachmentUri for thumbnail resolution
  when(
    event.getAttachmentUri(
      getThumbnail: anyNamed('getThumbnail'),
      width: anyNamed('width'),
      height: anyNamed('height'),
    ),
  ).thenAnswer(
    (_) async => Uri.parse('https://example.com/media'),
  );

  return event;
}

void main() {
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn('!room:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SharedMediaSection(
            roomId: mockRoom.id,
            loader: sharedMediaLoaderForRoom(mockRoom),
            avatarResolver: ClientAvatarResolver(mockClient),
          ),
        ),
      ),
    );
  }

  group('SharedMediaSection', () {
    testWidgets('shows loading indicator while fetching media', (tester) async {
      final completer = Completer<_SearchResult>();
      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('SHARED MEDIA'), findsOneWidget);

      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('shows empty state when no media found', (tester) async {
      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => _result());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No shared media yet'), findsOneWidget);
    });

    testWidgets('shows file list for file events', (tester) async {
      final fileEvent = _makeEvent(
        MessageTypes.File,
        body: 'document.pdf',
        info: {'size': 1048576},
      );

      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => _result(events: [fileEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_rounded), findsOneWidget);
    });

    testWidgets('shows audio icon for audio events', (tester) async {
      final audioEvent = _makeEvent(
        MessageTypes.Audio,
        body: 'recording.mp3',
        info: {'size': 512},
      );

      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => _result(events: [audioEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('recording.mp3'), findsOneWidget);
      expect(find.text('512 B'), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack_rounded), findsOneWidget);
    });

    testWidgets('shows Load more button when there is a next batch',
        (tester) async {
      final fileEvent = _makeEvent(MessageTypes.File, body: 'file.txt');

      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => _result(events: [fileEvent], nextBatch: 'batch2'),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('hides Load more when no next batch', (tester) async {
      final fileEvent = _makeEvent(MessageTypes.File, body: 'file.txt');

      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => _result(events: [fileEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('handles load error gracefully', (tester) async {
      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenThrow(Exception('Network error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No shared media yet'), findsOneWidget);
    });

    testWidgets('shows image grid for image events', (tester) async {
      final imageEvent = _makeEvent(MessageTypes.Image, body: 'photo.jpg');

      when(
        mockRoom.searchEvents(
          searchFunc: anyNamed('searchFunc'),
          nextBatch: anyNamed('nextBatch'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => _result(events: [imageEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
    });
  });
}

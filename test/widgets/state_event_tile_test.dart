import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/state_event_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
])
import 'state_event_tile_test.mocks.dart';

void main() {
  late MockEvent mockEvent;
  late MockUser senderUser;
  late MockUser targetUser;
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockEvent = MockEvent();
    senderUser = MockUser();
    targetUser = MockUser();
    mockRoom = MockRoom();
    mockClient = MockClient();

    when(senderUser.calcDisplayname()).thenReturn('Bob Ross');
    when(targetUser.calcDisplayname()).thenReturn('Bob Ross');
    when(mockEvent.senderFromMemoryOrFallback).thenReturn(senderUser);
    when(mockEvent.senderId).thenReturn('@testuser2:example.com');
    when(mockEvent.roomId).thenReturn('!room:example.com');
    when(mockEvent.originServerTs).thenReturn(DateTime(2026, 1, 15, 14, 30));
    when(mockEvent.room).thenReturn(mockRoom);
    when(mockEvent.type).thenReturn(EventTypes.RoomMember);
    when(mockEvent.stateKey).thenReturn('@testuser2:example.com');
    when(mockRoom.client).thenReturn(mockClient);
    when(
      mockRoom.unsafeGetUserFromMemoryOrFallback(any),
    ).thenReturn(targetUser);
  });

  Widget wrap(Event event) =>
      MaterialApp(home: Scaffold(body: StateEventTile(event: event)));

  testWidgets(
    'displayname change uses previous name as subject, not new name',
    (tester) async {
      when(mockEvent.content).thenReturn({
        'membership': 'join',
        'displayname': 'Bob Ross',
      });
      when(mockEvent.prevContent).thenReturn({
        'membership': 'join',
        'displayname': 'testuser2',
      });

      await tester.pumpWidget(wrap(mockEvent));

      expect(
        find.text("testuser2 changed their display name to 'Bob Ross'"),
        findsOneWidget,
      );
      expect(
        find.text("Bob Ross changed their display name to 'Bob Ross'"),
        findsNothing,
      );
    },
  );

  testWidgets('falls back to MXID localpart when prev displayname is empty', (
    tester,
  ) async {
    when(mockEvent.content).thenReturn({
      'membership': 'join',
      'displayname': 'Bob Ross',
    });
    when(mockEvent.prevContent).thenReturn({'membership': 'join'});

    await tester.pumpWidget(wrap(mockEvent));

    expect(
      find.text("testuser2 changed their display name to 'Bob Ross'"),
      findsOneWidget,
    );
  });

  testWidgets('removing displayname uses previous name as subject', (
    tester,
  ) async {
    when(mockEvent.content).thenReturn({'membership': 'join'});
    when(mockEvent.prevContent).thenReturn({
      'membership': 'join',
      'displayname': 'Old Name',
    });

    await tester.pumpWidget(wrap(mockEvent));

    expect(find.text('Old Name removed their display name'), findsOneWidget);
  });
}

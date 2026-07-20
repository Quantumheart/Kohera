import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/services/member_sheet_launcher.dart';
import 'package:mockito/mockito.dart';

import 'report_room_content_test.mocks.dart';

void main() {
  KoheraRoomMember bannedMember({
    String userId = '@spam:example.com',
    String displayname = 'Spammer',
  }) =>
      KoheraRoomMember(
        userId: userId,
        displayname: displayname,
        membership: 'ban',
        powerLevel: 0,
      );

  testWidgets('unbanRoomMember calls client.unban and surfaces success snackbar',
      (tester) async {
    final client = MockClient();
    final room = MockRoom();
    when(room.id).thenReturn('!room:server');
    when(room.client).thenReturn(client);
    when(client.unban(any, any, reason: anyNamed('reason')))
        .thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => unbanRoomMember(
                  context,
                  room,
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
  });

  testWidgets('unbanRoomMember forwards reason when provided',
      (tester) async {
    final client = MockClient();
    final room = MockRoom();
    when(room.id).thenReturn('!room:server');
    when(room.client).thenReturn(client);
    when(client.unban(any, any, reason: anyNamed('reason')))
        .thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => unbanRoomMember(
                  context,
                  room,
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

    verify(client.unban('!room:server', '@spam:example.com', reason: 'spamming'))
        .called(1);
  });

  testWidgets('unbanRoomMember surfaces failure snackbar on error',
      (tester) async {
    final client = MockClient();
    final room = MockRoom();
    when(room.id).thenReturn('!room:server');
    when(room.client).thenReturn(client);
    when(client.unban(any, any, reason: anyNamed('reason')))
        .thenThrow(Exception('Permission denied'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => unbanRoomMember(
                  context,
                  room,
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

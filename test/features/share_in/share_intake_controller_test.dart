import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/incoming_share.dart';
import 'package:kohera/features/share_in/services/share_intake_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'share_intake_controller_test.mocks.dart';

IncomingShare _share({
  String roomId = '!room:server',
  String? text,
  List<IncomingShareFile> files = const [],
}) =>
    IncomingShare(roomId: roomId, text: text, files: files);

void main() {
  late MockClient client;
  late MockRoom room;

  setUp(() {
    client = MockClient();
    room = MockRoom();
    when(client.getRoomById('!room:server')).thenReturn(room);
    when(room.sendTextEvent(any)).thenAnswer((_) async => r'$event');
    when(room.sendFileEvent(any,
            threadRootEventId: anyNamed('threadRootEventId'),
            threadLastEventId: anyNamed('threadLastEventId')))
        .thenAnswer((_) async => r'$event');
  });

  test('text share sends text event', () async {
    await sendIncomingShareToRoom(client, '!room:server', _share(text: 'hi'));
    verify(room.sendTextEvent('hi')).called(1);
    verifyNever(room.sendFileEvent(any,
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId')));
  });

  test('file share reads bytes and sends file event', () async {
    final tmp = await Directory.systemTemp.createTemp('intake_test');
    final file = await File('${tmp.path}/pic.png').writeAsBytes([1, 2, 3]);
    await sendIncomingShareToRoom(
      client,
      '!room:server',
      _share(files: [
        IncomingShareFile(
          filePath: file.path,
          name: 'pic.png',
          mimeType: 'image/png',
        ),
      ]),
    );
    verify(room.sendFileEvent(any,
            threadRootEventId: anyNamed('threadRootEventId'),
            threadLastEventId: anyNamed('threadLastEventId')))
        .called(1);
    verifyNever(room.sendTextEvent(any));
    await tmp.delete(recursive: true);
  });

  test('text + file share sends both', () async {
    final tmp = await Directory.systemTemp.createTemp('intake_both');
    final file = await File('${tmp.path}/a.bin').writeAsBytes([9]);
    await sendIncomingShareToRoom(
      client,
      '!room:server',
      _share(text: 'caption', files: [
        IncomingShareFile(filePath: file.path, name: 'a.bin'),
      ]),
    );
    verify(room.sendTextEvent('caption')).called(1);
    verify(room.sendFileEvent(any,
            threadRootEventId: anyNamed('threadRootEventId'),
            threadLastEventId: anyNamed('threadLastEventId')))
        .called(1);
    await tmp.delete(recursive: true);
  });

  test('missing staged file is skipped, no throw', () async {
    await sendIncomingShareToRoom(
      client,
      '!room:server',
      _share(files: [
        const IncomingShareFile(filePath: '/no/such/file', name: 'x'),
      ]),
    );
    verifyNever(room.sendFileEvent(any,
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId')));
  });

  test('room not found throws', () async {
    expect(
      () => sendIncomingShareToRoom(client, '!gone:server', _share(text: 'x')),
      throwsA(isA<StateError>()),
    );
  });

  test('empty text is not sent', () async {
    await sendIncomingShareToRoom(client, '!room:server', _share(text: ''));
    verifyNever(room.sendTextEvent(any));
  });

  test('send error propagates', () async {
    when(room.sendTextEvent(any)).thenThrow(Exception('network down'));
    expect(
      () => sendIncomingShareToRoom(client, '!room:server', _share(text: 'x')),
      throwsA(isA<Exception>()),
    );
  });
}

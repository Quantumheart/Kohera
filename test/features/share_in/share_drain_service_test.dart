import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/pending_share.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/share_drain_service.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'share_drain_service_test.mocks.dart';

class _FakeShareStore implements ShareInStore {
  _FakeShareStore(List<PendingShare> initial) : _pending = [...initial];

  final List<PendingShare> _pending;

  @override
  Future<List<PendingShare>> readPendingShares() async =>
      List.unmodifiable(_pending);

  @override
  Future<void> clearPendingShare(String id) async {
    _pending.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> clearAllPendingShares() async => _pending.clear();

  @override
  Future<void> writeRoomSnapshot(List<RoomSnapshot> snapshots) async =>
      throw UnimplementedError();

  @override
  Future<List<RoomSnapshot>> readRoomSnapshot() async =>
      throw UnimplementedError();

  @override
  Future<String?> readActiveAccountId() async => throw UnimplementedError();

  @override
  Future<void> writeActiveAccountId(String accountId) async =>
      throw UnimplementedError();
}

PendingShare _textShare({
  required String id,
  String text = 'hello',
  String accountId = 'alice',
  String roomId = '!room:server',
}) =>
    PendingShare(
      id: id,
      targetRoomId: roomId,
      accountId: accountId,
      kind: PendingShareKind.text,
      createdAt: 0,
      text: text,
    );

PendingShare _fileShare({
  required String id,
  required String filePath,
  String? mimeType,
  String name = 'pic.png',
  String accountId = 'alice',
  String roomId = '!room:server',
}) =>
    PendingShare(
      id: id,
      targetRoomId: roomId,
      accountId: accountId,
      kind: PendingShareKind.file,
      createdAt: 0,
      filePath: filePath,
      mimeType: mimeType,
      originalFileName: name,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient aliceClient;
  late MockRoom room;

  setUp(() {
    aliceClient = MockClient();
    room = MockRoom();
    when(aliceClient.getRoomById('!room:server')).thenReturn(room);
    when(room.sendTextEvent(any)).thenAnswer((_) async => r'$event');
    when(room.sendFileEvent(any, threadRootEventId: anyNamed('threadRootEventId'), threadLastEventId: anyNamed('threadLastEventId')))
        .thenAnswer((_) async => r'$event');
  });

  Future<void> drainWith({
    required List<PendingShare> pending,
    Client? Function(String)? resolveClient,
  }) async {
    final store = _FakeShareStore(pending);
    final service = ShareDrainService(
      resolveClient: resolveClient ?? ((id) => id == 'alice' ? aliceClient : null),
      store: store,
    );
    await service.drainOnce();
    service.dispose();
  }

  test('text share is sent and cleared', () async {
    await drainWith(pending: [_textShare(id: 't1')]);
    verify(room.sendTextEvent('hello')).called(1);
  });

  test('file share reads bytes and sends, then clears', () async {
    final tmp = await Directory.systemTemp.createTemp('share_drain_test');
    final file = await File('${tmp.path}/pic.png').writeAsBytes([1, 2, 3, 4]);
    await drainWith(pending: [_fileShare(id: 'f1', filePath: file.path)]);
    verify(room.sendFileEvent(any,
            threadRootEventId: anyNamed('threadRootEventId'),
            threadLastEventId: anyNamed('threadLastEventId')))
        .called(1);
    await tmp.delete(recursive: true);
  });

  test('unknown account discards the entry without sending', () async {
    final store = _FakeShareStore([_textShare(id: 't2', accountId: 'ghost')]);
    final service = ShareDrainService(
      resolveClient: (_) => null,
      store: store,
    );
    await service.drainOnce();
    service.dispose();
    verifyNever(room.sendTextEvent(any));
    expect(await store.readPendingShares(), isEmpty);
  });

  test('room left discards the entry without sending', () async {
    when(aliceClient.getRoomById('!gone:server')).thenReturn(null);
    await drainWith(
      pending: [_textShare(id: 't3', roomId: '!gone:server')],
    );
    verifyNever(room.sendTextEvent(any));
  });

  test('missing staged file discards the entry without throwing', () async {
    await drainWith(
      pending: [_fileShare(id: 'f2', filePath: '/no/such/file.png')],
    );
    verifyNever(room.sendFileEvent(any,
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId')));
  });

  test('empty text discards the entry without sending', () async {
    await drainWith(pending: [_textShare(id: 't4', text: '')]);
    verifyNever(room.sendTextEvent(any));
  });

  test('transient send error leaves the entry to retry', () async {
    when(room.sendTextEvent(any)).thenThrow(Exception('network down'));
    final store = _FakeShareStore([_textShare(id: 't5')]);
    final service = ShareDrainService(
      resolveClient: (_) => aliceClient,
      store: store,
    );
    await service.drainOnce();
    service.dispose();
    final remaining = await store.readPendingShares();
    expect(remaining.single.id, 't5');
  });

  test('duplicate ids are sent only once', () async {
    await drainWith(
      pending: [_textShare(id: 'dup'), _textShare(id: 'dup')],
    );
    verify(room.sendTextEvent('hello')).called(1);
  });

  test('multiple distinct shares all drain', () async {
    final tmp = await Directory.systemTemp.createTemp('share_drain_multi');
    final file = await File('${tmp.path}/a.bin').writeAsBytes([9, 9]);
    await drainWith(
      pending: [
        _textShare(id: 'm1', text: 'one'),
        _textShare(id: 'm2', text: 'two'),
        _fileShare(id: 'm3', filePath: file.path),
      ],
    );
    verify(room.sendTextEvent('one')).called(1);
    verify(room.sendTextEvent('two')).called(1);
    verify(room.sendFileEvent(any,
            threadRootEventId: anyNamed('threadRootEventId'),
            threadLastEventId: anyNamed('threadLastEventId')))
        .called(1);
    await tmp.delete(recursive: true);
  });
}

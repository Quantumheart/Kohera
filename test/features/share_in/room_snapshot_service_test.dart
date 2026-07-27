import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/share_in/models/room_snapshot.dart';
import 'package:kohera/features/share_in/services/room_snapshot_service.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'room_snapshot_service_test.mocks.dart';

class _RecordingSink implements RoomSnapshotSink {
  final List<List<RoomSnapshot>> writes = [];

  @override
  Future<void> writeRoomSnapshot(List<RoomSnapshot> snapshots) async {
    writes.add(List.unmodifiable(snapshots));
  }
}

MockRoom _room({
  required String id,
  required String displayname,
  required Membership membership,
  bool isSpace = false,
  String? avatarMxc,
}) {
  final r = MockRoom();
  when(r.id).thenReturn(id);
  when(r.getLocalizedDisplayname()).thenReturn(displayname);
  when(r.membership).thenReturn(membership);
  when(r.isSpace).thenReturn(isSpace);
  when(r.avatar).thenReturn(avatarMxc == null ? null : Uri.parse(avatarMxc));
  return r;
}

void main() {
  late MockClient client;
  late CachedStreamController<SyncUpdate> syncController;
  late _RecordingSink sink;

  setUp(() {
    client = MockClient();
    syncController = CachedStreamController<SyncUpdate>();
    sink = _RecordingSink();
    when(client.onSync).thenReturn(syncController);
  });

  RoomSnapshotService startService({Duration debounce = const Duration(seconds: 10)}) {
    return RoomSnapshotService(
      client: client,
      sink: sink,
      debounce: debounce,
    )..start();
  }

  test('writes snapshots of joined, non-space rooms only', () {
    final rooms = [
      _room(id: '!join:s', displayname: 'Joined', membership: Membership.join),
      _room(
        id: '!space:s',
        displayname: 'Space',
        membership: Membership.join,
        isSpace: true,
      ),
      _room(id: '!invite:s', displayname: 'Invite', membership: Membership.invite),
      _room(id: '!left:s', displayname: 'Left', membership: Membership.leave),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final service = startService();
      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(sink.writes, hasLength(1));
      final written = sink.writes.single;
      expect(written, hasLength(1));
      expect(written.single.roomId, '!join:s');
      expect(written.single.displayname, 'Joined');

      service.dispose();
    });
  });

  test('includes avatar mxc when present', () {
    final rooms = [
      _room(
        id: '!a:s',
        displayname: 'A',
        membership: Membership.join,
        avatarMxc: 'mxc://srv/abc',
      ),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final service = startService();
      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(sink.writes.single.single.avatarMxc, 'mxc://srv/abc');
      service.dispose();
    });
  });

  test('throttles: multiple syncs within debounce produce a single write', () {
    final rooms = [
      _room(id: '!a:s', displayname: 'A', membership: Membership.join),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final service = startService();
      for (var i = 0; i < 5; i++) {
        syncController.add(SyncUpdate(nextBatch: ''));
      }
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(sink.writes, hasLength(1));

      service.dispose();
    });
  });

  test('a second sync after the flush triggers a new write', () {
    final rooms = [
      _room(id: '!a:s', displayname: 'A', membership: Membership.join),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final service = startService();
      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(sink.writes, hasLength(1));

      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(sink.writes, hasLength(2));

      service.dispose();
    });
  });

  test('dispose cancels the pending flush (no write after dispose)', () {
    final rooms = [
      _room(id: '!a:s', displayname: 'A', membership: Membership.join),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final service = startService();
      syncController.add(SyncUpdate(nextBatch: ''));
      service.dispose();
      async.elapse(const Duration(seconds: 20));
      async.flushMicrotasks();

      expect(sink.writes, isEmpty);
    });
  });
}

import 'dart:async';

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
    // Keep the initial launch flush pending so sync-driven tests stay
    // isolated; tests that exercise the initial flush override this stub.
    when(client.roomsLoading).thenAnswer((_) => Completer<void>().future);
  });

  RoomSnapshotService startService({Duration flushInterval = const Duration(seconds: 10)}) {
    return RoomSnapshotService(
      client: client,
      sink: sink,
      flushInterval: flushInterval,
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

  test('throttles: continuous syncs within the interval still flush once', () {
    final rooms = [
      _room(id: '!a:s', displayname: 'A', membership: Membership.join),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final service = startService();
      // Long-polling-like cadence: events spread across the window.
      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 3));
      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 3));
      syncController.add(SyncUpdate(nextBatch: ''));
      async.elapse(const Duration(seconds: 4));
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

  test('writes an initial snapshot at start once rooms are loaded', () {
    final rooms = [
      _room(id: '!a:s', displayname: 'A', membership: Membership.join),
    ];
    when(client.rooms).thenReturn(rooms);

    fakeAsync((async) {
      final loaded = Completer<void>();
      when(client.roomsLoading).thenAnswer((_) => loaded.future);
      final service = startService();
      expect(sink.writes, isEmpty);

      loaded.complete();
      async.flushMicrotasks();

      expect(sink.writes, hasLength(1));
      expect(sink.writes.single.single.roomId, '!a:s');

      service.dispose();
    });
  });
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/outbox_database.dart';
import 'package:kohera/core/services/sub_services/outbox_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'outbox_service_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
])
class _StubDatabase extends Fake implements DatabaseApi {
  _StubDatabase({this.sendingByRoom = const {}, this.allByRoom = const {}});
  final Map<String, List<Event>> sendingByRoom;
  final Map<String, List<Event>> allByRoom;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async =>
      onlySending
          ? (sendingByRoom[room.id] ?? const [])
          : (allByRoom[room.id] ?? const []);
}

class _MemoryOutboxDb extends OutboxDatabase {
  _MemoryOutboxDb() : super(clientName: '_test_');
  final Map<String, OutboxAttempt> _store = {};

  @override
  Future<List<OutboxAttempt>> all() async => _store.values.toList();

  @override
  Future<void> upsert(OutboxAttempt entry) async {
    _store[entry.txid] = entry;
  }

  @override
  Future<void> remove(String txid) async {
    _store.remove(txid);
  }

  @override
  Future<void> retainOnly(Set<String> txids) async {
    _store.removeWhere((k, _) => !txids.contains(k));
  }

  @override
  Future<void> close() async {}
}

Event _stubEvent({
  required String txid,
  required String eventId,
  required EventStatus status,
}) {
  final ev = MockEvent();
  when(ev.transactionId).thenReturn(txid);
  when(ev.eventId).thenReturn(eventId);
  when(ev.status).thenReturn(status);
  when(ev.sendAgain(txid: anyNamed('txid')))
      .thenAnswer((_) async => null);
  return ev;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient client;
  late MockRoom room;
  late CachedStreamController<Event> timelineController;

  setUp(() {
    client = MockClient();
    room = MockRoom();
    timelineController = CachedStreamController<Event>();
    when(room.id).thenReturn('!r:s');
    when(client.rooms).thenReturn([room]);
    when(client.getRoomById('!r:s')).thenReturn(room);
    when(client.onTimelineEvent).thenReturn(timelineController);
    when(client.onSync).thenAnswer(
      (_) => CachedStreamController<SyncUpdate>(),
    );
  });

  test('initial scan enqueues error events and skips synced', () async {
    final stuck = _stubEvent(
      txid: 'tx1',
      eventId: r'$tx1',
      status: EventStatus.error,
    );
    when(client.database).thenReturn(
      _StubDatabase(sendingByRoom: {'!r:s': [stuck]}),
    );
    final service = OutboxService(
      client: client,
      clientName: 'test',
      databaseOverride: _MemoryOutboxDb(),
      backoffOverride: (_) => const Duration(hours: 1),
    );
    await service.start();
    await service.runScanForTest();
    expect(service.entries.keys, contains('tx1'));
    expect(service.entries['tx1']!.attempts, 0);
    service.dispose();
  });

  test('synced timeline event evicts matching entry', () {
    fakeAsync((async) {
      final stuck = _stubEvent(
        txid: 'tx2',
        eventId: r'$tx2',
        status: EventStatus.error,
      );
      when(client.database).thenReturn(
        _StubDatabase(sendingByRoom: {'!r:s': [stuck]}),
      );
      final service = OutboxService(
        client: client,
        clientName: 'test',
        databaseOverride: _MemoryOutboxDb(),
        backoffOverride: (_) => const Duration(hours: 1),
      );
      unawaited(service.start());
      unawaited(service.runScanForTest());
      async.flushMicrotasks();
      expect(service.entries.containsKey('tx2'), isTrue);

      final synced = _stubEvent(
        txid: 'tx2',
        eventId: r'$tx2',
        status: EventStatus.synced,
      );
      timelineController.add(synced);
      async.flushMicrotasks();
      expect(service.entries.containsKey('tx2'), isFalse);
      service.dispose();
    });
  });

  test('reaction de-dup: synced event in db prevents sendAgain', () async {
    final stuck = _stubEvent(
      txid: 'tx3',
      eventId: r'$tx3',
      status: EventStatus.error,
    );
    final accepted = _stubEvent(
      txid: 'tx3',
      eventId: r'$server_id',
      status: EventStatus.synced,
    );
    when(client.database).thenReturn(
      _StubDatabase(
        sendingByRoom: {'!r:s': [stuck]},
        allByRoom: {'!r:s': [accepted]},
      ),
    );
    final service = OutboxService(
      client: client,
      clientName: 'test',
      databaseOverride: _MemoryOutboxDb(),
      backoffOverride: (_) => const Duration(hours: 1),
    );
    await service.start();
    await service.runScanForTest();
    await service.retryNowForTest('tx3');
    verifyNever(stuck.sendAgain(txid: anyNamed('txid')));
    expect(service.entries.containsKey('tx3'), isFalse);
    service.dispose();
  });

  test('attempt cap marks final-failed and stops retrying', () async {
    final stuck = _stubEvent(
      txid: 'tx4',
      eventId: r'$tx4',
      status: EventStatus.error,
    );
    when(client.database).thenReturn(
      _StubDatabase(sendingByRoom: {'!r:s': [stuck]}),
    );
    final service = OutboxService(
      client: client,
      clientName: 'test',
      databaseOverride: _MemoryOutboxDb(),
      backoffOverride: (_) => Duration.zero,
    );
    await service.start();
    await service.runScanForTest();
    for (var i = 0; i < OutboxService.kMaxAttempts; i++) {
      await service.retryNowForTest('tx4');
    }
    final view = service.entries['tx4']!;
    expect(view.attempts, OutboxService.kMaxAttempts);
    expect(view.finalFailed, isTrue);
    service.dispose();
  });

  group('computeBackoff', () {
    test('caps at 60s after attempt 6', () {
      final service = OutboxService(
        client: client,
        clientName: 'test',
        databaseOverride: _MemoryOutboxDb(),
      );
      when(client.database).thenReturn(_StubDatabase());
      for (final attempts in [6, 7, 8, 12]) {
        final d = service.computeBackoff(attempts);
        expect(
          d.inMilliseconds,
          inInclusiveRange(60 * 750, 60 * 1250),
          reason: 'attempts=$attempts produced ${d.inMilliseconds}ms',
        );
      }
      service.dispose();
    });

    test('doubles base before cap', () {
      final service = OutboxService(
        client: client,
        clientName: 'test',
        databaseOverride: _MemoryOutboxDb(),
      );
      when(client.database).thenReturn(_StubDatabase());
      Duration mid(int attempts) => service.computeBackoff(attempts);
      final a1 = mid(1).inMilliseconds;
      final a3 = mid(3).inMilliseconds;
      expect(a1, inInclusiveRange(2 * 750, 2 * 1250));
      expect(a3, inInclusiveRange(8 * 750, 8 * 1250));
      service.dispose();
    });
  });

  test('fake_async: retry fires after scheduled delay', () {
    fakeAsync((async) {
      final stuck = _stubEvent(
        txid: 'tx5',
        eventId: r'$tx5',
        status: EventStatus.error,
      );
      when(client.database).thenReturn(
        _StubDatabase(sendingByRoom: {'!r:s': [stuck]}),
      );
      final service = OutboxService(
        client: client,
        clientName: 'test',
        databaseOverride: _MemoryOutboxDb(),
        backoffOverride: (_) => const Duration(seconds: 5),
      );
      unawaited(service.start());
      unawaited(service.runScanForTest());
      async.flushMicrotasks();
      verifyNever(stuck.sendAgain(txid: anyNamed('txid')));
      async.elapse(const Duration(seconds: 6));
      verify(stuck.sendAgain(txid: 'tx5')).called(greaterThanOrEqualTo(1));
      service.dispose();
    });
  });
}

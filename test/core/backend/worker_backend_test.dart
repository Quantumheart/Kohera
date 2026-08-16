// coverage:ignore-file

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/adapters/stub_worker_handler.dart';
import 'package:kohera/core/backend/backend.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

void main() {
  late WorkerBackend backend;

  setUp(() {
    backend = WorkerBackend(handlerFactory: StubWorkerHandler.new);
  });

  tearDown(() async {
    if (backend.isReady) await backend.disconnect();
  });

  test('connect spawns the worker and isReady becomes true', () async {
    expect(backend.isReady, false);
    await backend.connect();
    expect(backend.isReady, true);
  });

  test('accountsList returns empty list via the stub handler', () async {
    await backend.connect();
    final accounts = await backend.accountsList();
    expect(accounts, isEmpty);
  });

  test('roomsList returns empty list via the stub handler', () async {
    await backend.connect();
    final rooms = await backend.roomsList('default');
    expect(rooms, isEmpty);
  });

  test('roomListUpdates is a listenable stream (stub never fires events)',
      () async {
    await backend.connect();
    expect(backend.roomListUpdates('default'), isA<Stream<List<RoomDto>>>());
  });

  test('disconnect kills the isolate and isReady becomes false', () async {
    await backend.connect();
    expect(backend.isReady, true);
    await backend.disconnect();
    expect(backend.isReady, false);
  });

  test('calling an op after disconnect throws StateError', () async {
    await backend.connect();
    await backend.disconnect();
    expect(
      () => backend.roomsList('default'),
      throwsA(isA<StateError>()),
    );
  });

  test('onLoginStateChanged is a broadcast stream', () async {
    expect(backend.onLoginStateChanged, isA<Stream<String>>());
  });

  test('onError is a broadcast stream', () async {
    expect(backend.onError, isA<Stream<BackendError>>());
  });
}

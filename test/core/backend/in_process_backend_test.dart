// coverage:ignore-file

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/in_process_backend.dart';
import 'package:kohera/core/backend/protocol.dart';

void main() {
  late InProcessBackend backend;

  setUp(() => backend = InProcessBackend());
  tearDown(() => backend.disconnect());

  test('connect sets isReady', () async {
    expect(backend.isReady, false);
    await backend.connect();
    expect(backend.isReady, true);
  });

  test('disconnect clears isReady', () async {
    await backend.connect();
    expect(backend.isReady, true);
    await backend.disconnect();
    expect(backend.isReady, false);
  });

  test('accountsList returns empty by default', () async {
    final accounts = await backend.accountsList();
    expect(accounts, isEmpty);
  });

  test('roomsList returns empty for any account', () async {
    final rooms = await backend.roomsList('default');
    expect(rooms, isEmpty);
  });

  test('roomListUpdates is an empty stream', () async {
    final events = await backend.roomListUpdates('default').toList();
    expect(events, isEmpty);
  });

  test('onLoginStateChanged is a broadcast stream', () async {
    expect(backend.onLoginStateChanged, isA<Stream<String>>());
  });

  test('onError is a broadcast stream', () async {
    expect(backend.onError, isA<Stream<BackendError>>());
  });
}

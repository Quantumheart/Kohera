// coverage:ignore-file

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/dto.dart';
import 'package:kohera/core/backend/matrix_sdk_worker_handler.dart';
import 'package:kohera/core/backend/worker_backend.dart';

/// Path to a copy of a real session DB for integration testing.
/// Create it by copying the production DB:
///   cp ~/.local/share/io.github.quantumheart.kohera/kohera_default.db \
///      test/fixtures/test_session.db
const _testDbPath = 'test/fixtures/test_session.db';

bool _hasTestDb() => File(_testDbPath).existsSync();

void main() {
  group('MatrixSdkWorkerHandler (unit, no DB needed)', () {
    test('can be constructed and disposed without init', () async {
      final handler = MatrixSdkWorkerHandler(
        dbPath: '/nonexistent',
        clientName: 'test',
      );
      await handler.dispose();
    });
  });

  group('MatrixSdkWorkerHandler (integration, needs test DB)', () {
    // These tests require a real session DB to restore from. They are skipped
    // if the test DB does not exist. To enable: copy your production DB to
    // test/fixtures/test_session.db (see the path above).
    test('hostSdk connects and serves accounts', skip: !_hasTestDb(), () async {
      final backend = WorkerBackend.hostSdk(
        dbPath: _testDbPath,
        clientName: 'test',
      );

      await backend.connect();
      expect(backend.isReady, true);

      final accounts = await backend.accountsList();
      expect(accounts, isNotEmpty);
      expect(accounts.first.isLoggedIn, true);

      await backend.disconnect();
      expect(backend.isReady, false);
    });

    test('hostSdk serves rooms list', skip: !_hasTestDb(), () async {
      final backend = WorkerBackend.hostSdk(
        dbPath: _testDbPath,
        clientName: 'test',
      );

      await backend.connect();
      final rooms = await backend.roomsList('test');
      // The list may be empty if the account has no rooms, but the call
      // should not throw.
      expect(rooms, isA<List<RoomDto>>());

      await backend.disconnect();
    });

    test('hostSdk disconnect rejects pending calls', skip: !_hasTestDb(), () async {
      final backend = WorkerBackend.hostSdk(
        dbPath: _testDbPath,
        clientName: 'test',
      );

      await backend.connect();
      await backend.disconnect();

      expect(
        () => backend.roomsList('test'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

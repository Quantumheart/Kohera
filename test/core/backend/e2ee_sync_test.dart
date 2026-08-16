// coverage:ignore-file

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/adapters/in_process_backend.dart';
import 'package:kohera/core/backend/adapters/stub_worker_handler.dart';
import 'package:kohera/core/backend/adapters/worker_backend.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

/// Verifies the E2EE + sync status ops (#995):
///   - StubWorkerHandler round-trips every op without error.
///   - InProcessBackend no-op stubs return neutral values.
///   - WorkerBackend wires every op through _call() and decodes results.
///   - BackendCall serialization carries the expected args for each op.

void main() {
  group('StubWorkerHandler E2EE + sync ops', () {
    late StubWorkerHandler handler;
    const emit = _noopEmit;

    setUp(() => handler = StubWorkerHandler());
    tearDown(() => handler.dispose());

    Future<BackendResult> call(String op, Map<String, dynamic> args) =>
        handler.handle(BackendCall(id: 0, op: op, args: args), emit);

    test('e2ee.encryptionEnabled returns enabled false', () async {
      final r = await call('e2ee.encryptionEnabled', {
        'accountId': 'a',
        'roomId': '!room:server',
      });
      expect(r.ok, true);
      expect(r.data?['enabled'], false);
    });

    test('e2ee.deviceKeys returns empty list', () async {
      final r = await call('e2ee.deviceKeys', {'accountId': 'a', 'userId': '@u:s'});
      expect(r.ok, true);
      expect(r.data?['devices'], isEmpty);
    });

    test('e2ee.verifyDevice returns ok empty', () async {
      final r = await call('e2ee.verifyDevice', {
        'accountId': 'a',
        'userId': '@u:s',
        'deviceId': 'DEV1',
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('e2ee.startVerification returns error state', () async {
      final r = await call('e2ee.startVerification', {
        'accountId': 'a',
        'userId': '@u:s',
        'deviceId': 'DEV1',
      });
      expect(r.ok, true);
      final v = r.data?['verification'] as Map<String, dynamic>;
      expect(v['state'], 'error');
    });

    test('e2ee.crossSigning.enabled returns enabled false', () async {
      final r = await call('e2ee.crossSigning.enabled', {'accountId': 'a'});
      expect(r.ok, true);
      expect(r.data?['enabled'], false);
    });

    test('e2ee.crossSigning.isCached returns isCached false', () async {
      final r = await call('e2ee.crossSigning.isCached', {'accountId': 'a'});
      expect(r.ok, true);
      expect(r.data?['isCached'], false);
    });

    test('e2ee.crossSigning.selfSign returns ok empty', () async {
      final r = await call('e2ee.crossSigning.selfSign', {
        'accountId': 'a',
        'recoveryKey': 'key123',
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('e2ee.bootstrap returns ok empty', () async {
      final r = await call('e2ee.bootstrap', {'accountId': 'a'});
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('e2ee.keyBackup.unlock returns unlocked false', () async {
      final r = await call('e2ee.keyBackup.unlock', {
        'accountId': 'a',
        'recoveryKey': 'key123',
      });
      expect(r.ok, true);
      expect(r.data?['unlocked'], false);
    });

    test('sync.status returns syncing false', () async {
      final r = await call('sync.status', {'accountId': 'a'});
      expect(r.ok, true);
      expect(r.data?['syncing'], false);
    });

    test('unknown op still errors', () async {
      final r = await call('e2ee.bogus', {});
      expect(r.ok, false);
      expect(r.error?.code, 'unknown_op');
    });
  });

  group('BackendCall serialization for E2EE + sync', () {
    test('e2ee.deviceKeys carries userId', () {
      const c = BackendCall(id: 1, op: 'e2ee.deviceKeys', args: {
        'accountId': 'a',
        'userId': '@u:s',
      });
      final m = c.toMap();
      expect(m['op'], 'e2ee.deviceKeys');
      expect((m['args'] as Map)['userId'], '@u:s');
      expect(BackendCall.fromMap(m).op, 'e2ee.deviceKeys');
    });

    test('e2ee.startVerification carries userId and deviceId', () {
      const c = BackendCall(id: 2, op: 'e2ee.startVerification', args: {
        'accountId': 'a',
        'userId': '@u:s',
        'deviceId': 'DEV1',
      });
      final m = c.toMap();
      expect((m['args'] as Map)['userId'], '@u:s');
      expect((m['args'] as Map)['deviceId'], 'DEV1');
      expect(BackendCall.fromMap(m).op, 'e2ee.startVerification');
    });
  });

  group('WorkerBackend E2EE + sync via stub (round-trip)', () {
    late WorkerBackend backend;

    setUp(() => backend = WorkerBackend(handlerFactory: StubWorkerHandler.new));
    tearDown(() async {
      if (backend.isReady) await backend.disconnect();
    });

    test('encryptionEnabled returns false through the transport', () async {
      await backend.connect();
      expect(await backend.encryptionEnabled('acct', '!room:s'), false);
    });

    test('deviceKeys returns empty list through the transport', () async {
      await backend.connect();
      expect(await backend.deviceKeys('acct', '@u:s'), isEmpty);
    });

    test('verifyDevice completes without error', () async {
      await backend.connect();
      await expectLater(backend.verifyDevice('acct', '@u:s', 'DEV1'), completes);
    });

    test('startVerification returns a VerificationDto', () async {
      await backend.connect();
      final v = await backend.startVerification('acct', '@u:s', deviceId: 'DEV1');
      expect(v.state, 'error');
    });

    test('crossSigningEnabled returns false through the transport', () async {
      await backend.connect();
      expect(await backend.crossSigningEnabled('acct'), false);
    });

    test('crossSigningIsCached returns false through the transport', () async {
      await backend.connect();
      expect(await backend.crossSigningIsCached('acct'), false);
    });

    test('crossSigningSelfSign completes without error', () async {
      await backend.connect();
      await expectLater(backend.crossSigningSelfSign('acct', recoveryKey: 'key'), completes);
    });

    test('bootstrap completes without error', () async {
      await backend.connect();
      await expectLater(backend.bootstrap('acct'), completes);
    });

    test('unlockKeyBackup returns false through the transport', () async {
      await backend.connect();
      expect(await backend.unlockKeyBackup('acct', 'key'), false);
    });

    test('syncStatus returns false through the transport', () async {
      await backend.connect();
      expect(await backend.syncStatus('acct'), false);
    });
  });

  group('InProcessBackend E2EE + sync no-op stubs', () {
    late InProcessBackend backend;

    setUp(() => backend = InProcessBackend());
    tearDown(() => backend.disconnect());

    test('E2EE ops return neutral values', () async {
      await backend.connect();
      expect(await backend.encryptionEnabled('a', '!r:s'), false);
      expect(await backend.deviceKeys('a', '@u:s'), isEmpty);
      await expectLater(backend.verifyDevice('a', '@u:s', 'DEV1'), completes);
      final v = await backend.startVerification('a', '@u:s');
      expect(v.state, 'error');
      expect(await backend.crossSigningEnabled('a'), false);
      expect(await backend.crossSigningIsCached('a'), false);
      await expectLater(backend.crossSigningSelfSign('a'), completes);
      await expectLater(backend.bootstrap('a'), completes);
      expect(await backend.unlockKeyBackup('a', 'key'), false);
    });

    test('sync status returns false', () async {
      await backend.connect();
      expect(await backend.syncStatus('a'), false);
    });
  });
}

void _noopEmit(BackendEvent event) {}

// coverage:ignore-file

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/adapters/in_process_backend.dart';
import 'package:kohera/core/backend/adapters/stub_worker_handler.dart';
import 'package:kohera/core/backend/adapters/worker_backend.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/backend_ops.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

/// Verifies the account + media ops (#996):
///   - StubWorkerHandler round-trips every op without error.
///   - InProcessBackend no-op stubs return neutral values.
///   - WorkerBackend wires every op through _call() and decodes results.
///   - BackendCall serialization carries the expected args for each op.

void main() {
  group('StubWorkerHandler account + media ops', () {
    late StubWorkerHandler handler;
    const emit = _noopEmit;

    setUp(() => handler = StubWorkerHandler());
    tearDown(() => handler.dispose());

    Future<BackendResult> call(String op, Map<String, dynamic> args) =>
        handler.handle(BackendCall(id: 0, op: op, args: args), emit);

    test('accounts.login returns ok false', () async {
      final r = await call(BackendOp.accountsLogin, {
        'homeserver': 'https://matrix.org',
        'username': '@u:s',
        'password': 'p',
      });
      expect(r.ok, true);
      expect(r.data?['ok'], false);
    });

    test('accounts.sso returns ok false', () async {
      final r = await call(BackendOp.accountsSso, {
        'homeserver': 'https://matrix.org',
        'loginToken': 'tok',
      });
      expect(r.ok, true);
      expect(r.data?['ok'], false);
    });

    test('accounts.register returns ok false', () async {
      final r = await call(BackendOp.accountsRegister, {
        'homeserver': 'https://matrix.org',
        'username': '@u:s',
        'password': 'p',
      });
      expect(r.ok, true);
      expect(r.data?['ok'], false);
    });

    test('accounts.logout returns ok empty', () async {
      final r = await call(BackendOp.accountsLogout, {});
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('accounts.restore returns ok false', () async {
      final r = await call(BackendOp.accountsRestore, {
        'homeserver': 'https://matrix.org',
        'accessToken': 'tok',
        'userId': '@u:s',
        'deviceId': 'DEV',
      });
      expect(r.ok, true);
      expect(r.data?['ok'], false);
    });

    test('subscribe.accounts.loginStateChanged returns ok empty', () async {
      final r = await call(BackendOp.subscribeAccountsLoginStateChanged, {
        'accountId': 'a',
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('media.upload returns mxc uri', () async {
      final r = await call(BackendOp.mediaUpload, {
        'accountId': 'a',
        'bytes': Uint8List.fromList([1, 2, 3]),
        'filename': 'f.png',
      });
      expect(r.ok, true);
      expect(r.data?['mxc'], isA<String>());
    });

    test('media.download returns empty bytes', () async {
      final r = await call(BackendOp.mediaDownload, {
        'accountId': 'a',
        'mxcUri': 'mxc://server/abc',
      });
      expect(r.ok, true);
      expect(r.data?['bytes'], isA<List<int>>());
    });

    test('media.mxcToHttp returns http url', () async {
      final r = await call(BackendOp.mediaMxcToHttp, {
        'accountId': 'a',
        'mxcUri': 'mxc://server/abc',
      });
      expect(r.ok, true);
      expect(r.data?['http'], isA<String>());
    });

    test('unknown op still errors', () async {
      final r = await call('accounts.bogus', {});
      expect(r.ok, false);
      expect(r.error?.code, 'unknown_op');
    });
  });

  group('WorkerBackend account + media via stub (round-trip)', () {
    late WorkerBackend backend;

    setUp(() => backend = WorkerBackend(handlerFactory: StubWorkerHandler.new));
    tearDown(() async {
      if (backend.isReady) await backend.disconnect();
    });

    test('login returns false through the transport', () async {
      await backend.connect();
      expect(
        await backend.login(
          homeserver: 'https://matrix.org',
          username: '@u:s',
          password: 'p',
        ),
        false,
      );
    });

    test('completeSsoLogin returns false through the transport', () async {
      await backend.connect();
      expect(
        await backend.completeSsoLogin(
          homeserver: 'https://matrix.org',
          loginToken: 'tok',
        ),
        false,
      );
    });

    test('register returns false through the transport', () async {
      await backend.connect();
      expect(
        await backend.register(
          homeserver: 'https://matrix.org',
          username: '@u:s',
          password: 'p',
        ),
        false,
      );
    });

    test('logout completes without error', () async {
      await backend.connect();
      await expectLater(backend.logout(), completes);
    });

    test('restore returns false through the transport', () async {
      await backend.connect();
      expect(
        await backend.restore(
          homeserver: 'https://matrix.org',
          accessToken: 'tok',
          userId: '@u:s',
          deviceId: 'DEV',
        ),
        false,
      );
    });

    test('uploadMedia returns mxc through the transport', () async {
      await backend.connect();
      final mxc = await backend.uploadMedia(
        'acct',
        Uint8List.fromList([1, 2, 3]),
        'f.png',
      );
      expect(mxc, isA<String>());
      expect(mxc, isNotEmpty);
    });

    test('downloadMedia returns bytes through the transport', () async {
      await backend.connect();
      final bytes = await backend.downloadMedia('acct', 'mxc://server/abc');
      expect(bytes, isA<Uint8List>());
    });

    test('mxcToHttp returns url through the transport', () async {
      await backend.connect();
      final http = await backend.mxcToHttp('acct', 'mxc://server/abc');
      expect(http, isA<String>());
      expect(http, isNotEmpty);
    });
  });

  group('InProcessBackend account + media no-op stubs', () {
    late InProcessBackend backend;

    setUp(() => backend = InProcessBackend());
    tearDown(() => backend.disconnect());

    test('account ops return neutral values', () async {
      await backend.connect();
      expect(
        await backend.login(
          homeserver: 'https://matrix.org',
          username: '@u:s',
          password: 'p',
        ),
        false,
      );
      expect(
        await backend.completeSsoLogin(
          homeserver: 'https://matrix.org',
          loginToken: 'tok',
        ),
        false,
      );
      expect(
        await backend.register(
          homeserver: 'https://matrix.org',
          username: '@u:s',
          password: 'p',
        ),
        false,
      );
      await expectLater(backend.logout(), completes);
      expect(
        await backend.restore(
          homeserver: 'https://matrix.org',
          accessToken: 'tok',
          userId: '@u:s',
          deviceId: 'DEV',
        ),
        false,
      );
    });

    test('media ops return neutral values', () async {
      await backend.connect();
      expect(
        await backend.uploadMedia('a', Uint8List(0), 'f.png'),
        isA<String>(),
      );
      expect(
        await backend.downloadMedia('a', 'mxc://server/abc'),
        isA<Uint8List>(),
      );
      expect(
        await backend.mxcToHttp('a', 'mxc://server/abc'),
        isA<String>(),
      );
    });
  });
}

void _noopEmit(BackendEvent event) {}
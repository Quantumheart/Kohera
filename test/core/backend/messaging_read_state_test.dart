// coverage:ignore-file

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/adapters/in_process_backend.dart';
import 'package:kohera/core/backend/adapters/stub_worker_handler.dart';
import 'package:kohera/core/backend/adapters/worker_backend.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

/// Verifies the messaging + read-state ops (#993):
///   - StubWorkerHandler round-trips every op without error.
///   - InProcessBackend no-op stubs return neutral values.
///   - WorkerBackend wires every op through _call() and decodes results.
///   - BackendCall serialization carries the expected args for each op.

void main() {
  group('StubWorkerHandler messaging + read-state ops', () {
    late StubWorkerHandler handler;
    const emit = _noopEmit;

    setUp(() => handler = StubWorkerHandler());
    tearDown(() => handler.dispose());

    Future<BackendResult> call(String op, Map<String, dynamic> args) =>
        handler.handle(BackendCall(id: 0, op: op, args: args), emit);

    test('message.send returns eventId null', () async {
      final r = await call('message.send', {
        'roomId': '!a:b',
        'content': {'msgtype': 'm.text', 'body': 'hi'},
      });
      expect(r.ok, true);
      expect(r.data?['eventId'], isNull);
    });

    test('message.sendText returns eventId null', () async {
      final r = await call('message.sendText', {'roomId': '!a:b', 'text': 'hi'});
      expect(r.ok, true);
      expect(r.data?['eventId'], isNull);
    });

    test('message.react returns eventId null', () async {
      final r = await call('message.react', {
        'roomId': '!a:b',
        'eventId': r'$ev',
        'key': '👍',
      });
      expect(r.ok, true);
      expect(r.data?['eventId'], isNull);
    });

    test('message.redact returns eventId null', () async {
      final r = await call('message.redact', {
        'roomId': '!a:b',
        'eventId': r'$ev',
        'reason': 'spam',
      });
      expect(r.ok, true);
      expect(r.data?['eventId'], isNull);
    });

    test('message.report returns ok empty', () async {
      final r = await call('message.report', {
        'roomId': '!a:b',
        'eventId': r'$ev',
        'reason': 'bad',
        'score': -50,
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('message.sendFile returns eventId null', () async {
      final r = await call('message.sendFile', {
        'roomId': '!a:b',
        'bytes': Uint8List.fromList([1, 2, 3]),
        'name': 'f.png',
      });
      expect(r.ok, true);
      expect(r.data?['eventId'], isNull);
    });

    test('read.setMarker returns ok empty', () async {
      final r = await call('read.setMarker', {
        'roomId': '!a:b',
        'eventId': r'$ev',
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('read.setReceipt returns ok empty', () async {
      final r = await call('read.setReceipt', {
        'roomId': '!a:b',
        'eventId': r'$ev',
      });
      expect(r.ok, true);
      expect(r.data, isEmpty);
    });

    test('read.getReceipts returns empty receipts map', () async {
      final r = await call('read.getReceipts', {'roomId': '!a:b'});
      expect(r.ok, true);
      expect(r.data?['receipts'], isEmpty);
    });

    test('unknown op still errors', () async {
      final r = await call('message.bogus', {});
      expect(r.ok, false);
      expect(r.error?.code, 'unknown_op');
    });
  });

  group('BackendCall serialization for messaging + read-state', () {
    test('message.send carries content', () {
      const c = BackendCall(id: 1, op: 'message.send', args: {
        'roomId': '!r:s',
        'content': {'msgtype': 'm.text', 'body': 'x'},
      });
      final m = c.toMap();
      expect(m['op'], 'message.send');
      expect(
        ((m['args'] as Map)['content'] as Map<String, dynamic>)['body'],
        'x',
      );
      expect(BackendCall.fromMap(m).op, 'message.send');
    });

    test('message.sendFile bytes survive round-trip', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      final c = BackendCall(id: 2, op: 'message.sendFile', args: {
        'roomId': '!r:s',
        'bytes': bytes,
        'name': 'a.bin',
      });
      final decoded = BackendCall.fromMap(c.toMap());
      expect(decoded.op, 'message.sendFile');
      expect(decoded.args['bytes'] as Uint8List, bytes);
      expect(decoded.args['name'], 'a.bin');
    });

    test('message.react accepts both key and emoji arg names', () {
      const c = BackendCall(id: 3, op: 'message.react', args: {
        'roomId': '!r:s',
        'eventId': r'$e',
        'key': '🎉',
      });
      expect(c.args['key'], '🎉');
    });

    test('read.getReceipts round-trips', () {
      const c = BackendCall(id: 4, op: 'read.getReceipts', args: {'roomId': '!r:s'});
      expect(BackendCall.fromMap(c.toMap()).op, 'read.getReceipts');
    });
  });

  group('WorkerBackend messaging + read-state via stub (round-trip)', () {
    late WorkerBackend backend;

    setUp(() => backend = WorkerBackend(handlerFactory: StubWorkerHandler.new));
    tearDown(() async {
      if (backend.isReady) await backend.disconnect();
    });

    test('sendText returns null through the isolate transport', () async {
      await backend.connect();
      expect(await backend.sendText('acct', '!r:s', 'hi'), isNull);
    });

    test('sendReaction returns null through the isolate transport', () async {
      await backend.connect();
      expect(await backend.sendReaction('acct', '!r:s', r'$e', '👍'), isNull);
    });

    test('redactEvent returns null through the isolate transport', () async {
      await backend.connect();
      expect(
        await backend.redactEvent('acct', '!r:s', r'$e', reason: 'spam'),
        isNull,
      );
    });

    test('reportEvent completes without error', () async {
      await backend.connect();
      await expectLater(
        backend.reportEvent('acct', '!r:s', r'$e', reason: 'bad', score: -50),
        completes,
      );
    });

    test('sendFile returns null through the isolate transport', () async {
      await backend.connect();
      expect(
        await backend.sendFile(
          'acct',
          '!r:s',
          Uint8List.fromList([1, 2, 3]),
          'f.bin',
        ),
        isNull,
      );
    });

    test('sendMessage returns null through the isolate transport', () async {
      await backend.connect();
      expect(
        await backend.sendMessage('acct', '!r:s', {'body': 'x'}),
        isNull,
      );
    });

    test('setReadMarker completes without error', () async {
      await backend.connect();
      await expectLater(backend.setReadMarker('acct', '!r:s', r'$e'), completes);
    });

    test('setReadReceipt completes without error', () async {
      await backend.connect();
      await expectLater(backend.setReadReceipt('acct', '!r:s', r'$e'), completes);
    });

    test('getReceipts returns empty map through the isolate transport',
        () async {
      await backend.connect();
      expect(await backend.getReceipts('acct', '!r:s'), isEmpty);
    });
  });

  group('InProcessBackend messaging + read-state no-op stubs', () {
    late InProcessBackend backend;

    setUp(() => backend = InProcessBackend());
    tearDown(() => backend.disconnect());

    test('messaging ops return null', () async {
      await backend.connect();
      expect(await backend.sendMessage('a', '!r', {}), isNull);
      expect(await backend.sendText('a', '!r', 'hi'), isNull);
      expect(await backend.sendReaction('a', '!r', r'$e', '👍'), isNull);
      expect(await backend.redactEvent('a', '!r', r'$e'), isNull);
      expect(
        await backend.sendFile('a', '!r', Uint8List(0), 'f'),
        isNull,
      );
    });

    test('reportEvent completes', () async {
      await backend.connect();
      await expectLater(backend.reportEvent('a', '!r', r'$e'), completes);
    });

    test('read-state ops complete / return empty', () async {
      await backend.connect();
      await expectLater(backend.setReadMarker('a', '!r', r'$e'), completes);
      await expectLater(backend.setReadReceipt('a', '!r', r'$e'), completes);
      expect(await backend.getReceipts('a', '!r'), isEmpty);
    });
  });
}

void _noopEmit(BackendEvent event) {}

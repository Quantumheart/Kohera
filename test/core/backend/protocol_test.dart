// coverage:ignore-file

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/backend/protocol.dart';

void main() {
  group('BackendCall codec', () {
    test('encode → decode round-trip preserves fields', () {
      const call = BackendCall(id: 42, op: 'rooms.list', args: {'accountId': 'default'});
      final encoded = encodeMessage(call);
      final decoded = decodeMessage(encoded) as BackendCall;

      expect(decoded.id, 42);
      expect(decoded.op, 'rooms.list');
      expect(decoded.args['accountId'], 'default');
    });

    test('kind tag is "call"', () {
      const encoded = <String, dynamic>{'k': 'call', 'id': 0, 'op': 'test', 'args': <String, dynamic>{}};
      expect(encodeMessage(const BackendCall(id: 0, op: 'test', args: {}))['k'], 'call');
      expect(encoded['k'], 'call');
    });
  });

  group('BackendReply codec', () {
    test('success reply round-trip', () {
      const reply = BackendReply(id: 42, ok: true, result: {'count': 3});
      final encoded = encodeMessage(reply);
      final decoded = decodeMessage(encoded) as BackendReply;

      expect(decoded.id, 42);
      expect(decoded.ok, true);
      expect(decoded.result!['count'], 3);
      expect(decoded.error, isNull);
    });

    test('error reply round-trip', () {
      const reply = BackendReply(
        id: 42,
        ok: false,
        error: BackendError(code: 'not_found', message: 'Room not found'),
      );
      final encoded = encodeMessage(reply);
      final decoded = decodeMessage(encoded) as BackendReply;

      expect(decoded.id, 42);
      expect(decoded.ok, false);
      expect(decoded.error!.code, 'not_found');
      expect(decoded.error!.message, 'Room not found');
      expect(decoded.error!.stackTrace, isNull);
    });

    test('error with stack trace round-trip', () {
      const reply = BackendReply(
        id: 7,
        ok: false,
        error: BackendError(
          code: 'crash',
          message: 'something broke',
          stackTrace: '#0 main',
        ),
      );
      final decoded = decodeMessage(encodeMessage(reply)) as BackendReply;

      expect(decoded.error!.stackTrace, '#0 main');
    });
  });

  group('BackendEvent codec', () {
    test('round-trip preserves name and payload', () {
      const event = BackendEvent(name: 'sync.update', payload: {'accountId': 'a1'});
      final decoded = decodeMessage(encodeMessage(event)) as BackendEvent;

      expect(decoded.name, 'sync.update');
      expect(decoded.payload['accountId'], 'a1');
    });

    test('kind tag is "event"', () {
      final encoded = encodeMessage(const BackendEvent(name: 'x', payload: {}));
      expect(encoded['k'], 'event');
    });
  });

  group('PendingCalls', () {
    test('resolve completes with result on success', () async {
      final pending = PendingCalls();
      final id = pending.nextId;
      final completer = Completer<Map<String, dynamic>>();
      pending.register(id, completer);

      final resolved =
          pending.resolve(const BackendReply(id: 0, ok: true, result: {'v': 1}));
      expect(resolved, true);
      final result = await completer.future;
      expect(result['v'], 1);
    });

    test('resolve completes with error on failure', () async {
      final pending = PendingCalls();
      final id = pending.nextId;
      final completer = Completer<Map<String, dynamic>>();
      pending.register(id, completer);

      pending.resolve(const BackendReply(
        id: 0,
        ok: false,
        error: BackendError(code: 'err', message: 'fail'),
      ));

      await expectLater(completer.future, throwsA(isA<BackendError>()));
    });

    test('resolve returns false for unknown id', () {
      final pending = PendingCalls();
      final result =
          pending.resolve(const BackendReply(id: 999, ok: true, result: {}));
      expect(result, false);
    });

    test('rejectAll errors every pending completer', () async {
      final pending = PendingCalls();
      final c1 = Completer<Map<String, dynamic>>();
      final c2 = Completer<Map<String, dynamic>>();
      pending.register(pending.nextId, c1);
      pending.register(pending.nextId, c2);

      pending.rejectAll('disconnected');

      await expectLater(c1.future, throwsA(equals('disconnected')));
      await expectLater(c2.future, throwsA(equals('disconnected')));
      expect(pending.pendingCount, 0);
    });
  });
}

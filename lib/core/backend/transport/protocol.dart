// coverage:ignore-file

import 'dart:async';

// ── Message envelope ─────────────────────────────────────────────
//
// Three message kinds flow over the SendPort/ReceivePort pair:
//
//   Call  — UI → worker:  invoke an op, expect a Reply with the same id.
//   Reply — worker → UI:  result or error for a Call.
//   Event — worker → UI:  unsolicited push (a stream fired on the worker).
//
// Every message is a plain Map<String, dynamic> on the wire so it can cross
// isolate boundaries without live SDK objects.  The [codec] helpers convert
// to/from typed wrappers.

/// A request from the UI to the worker to invoke a backend op.
class BackendCall {
  final int id;
  final String op;
  final Map<String, dynamic> args;

  const BackendCall({required this.id, required this.op, required this.args});

  Map<String, dynamic> toMap() => {'k': 'call', 'id': id, 'op': op, 'args': args};

  factory BackendCall.fromMap(Map<String, dynamic> m) =>
      BackendCall(id: m['id'] as int, op: m['op'] as String, args: m['args'] as Map<String, dynamic>);

  @override
  String toString() => 'BackendCall(#$id $op)';
}

/// A response from the worker to the UI for a [BackendCall].
class BackendReply {
  final int id;
  final bool ok;
  final Map<String, dynamic>? result;
  final BackendError? error;

  const BackendReply({required this.id, required this.ok, this.result, this.error});

  Map<String, dynamic> toMap() => {
        'k': 'reply',
        'id': id,
        'ok': ok,
        if (result != null) 'result': result,
        if (error != null) 'error': error!.toMap(),
      };

  factory BackendReply.fromMap(Map<String, dynamic> m) => BackendReply(
        id: m['id'] as int,
        ok: m['ok'] as bool,
        result: m['result'] as Map<String, dynamic>?,
        error: m['error'] != null
            ? BackendError.fromMap(m['error'] as Map<String, dynamic>)
            : null,
      );

  @override
  String toString() => ok ? 'BackendReply(#$id ok)' : 'BackendReply(#$id err: $error)';
}

/// An error returned in a [BackendReply].
class BackendError {
  final String code;
  final String message;
  final String? stackTrace;

  const BackendError({required this.code, required this.message, this.stackTrace});

  Map<String, dynamic> toMap() => {
        'code': code,
        'message': message,
        if (stackTrace != null) 'stack': stackTrace,
      };

  factory BackendError.fromMap(Map<String, dynamic> m) => BackendError(
        code: m['code'] as String,
        message: m['message'] as String,
        stackTrace: m['stack'] as String?,
      );

  @override
  String toString() => 'BackendError($code: $message)';
}

/// An unsolicited push from the worker to the UI (a stream fired on the worker).
class BackendEvent {
  final String name;
  final Map<String, dynamic> payload;

  const BackendEvent({required this.name, required this.payload});

  Map<String, dynamic> toMap() => {'k': 'event', 'name': name, 'payload': payload};

  factory BackendEvent.fromMap(Map<String, dynamic> m) => BackendEvent(
        name: m['name'] as String,
        payload: m['payload'] as Map<String, dynamic>,
      );

  @override
  String toString() => 'BackendEvent($name)';
}

// ── Codec ─────────────────────────────────────────────────────────

/// Encodes a typed message to a plain Map for sending across a SendPort.
Map<String, dynamic> encodeMessage(Object msg) {
  if (msg is BackendCall) return msg.toMap();
  if (msg is BackendReply) return msg.toMap();
  if (msg is BackendEvent) return msg.toMap();
  throw ArgumentError('Unknown message type: ${msg.runtimeType}');
}

/// Decodes a plain Map received from a ReceivePort back to a typed message.
Object decodeMessage(Map<String, dynamic> m) {
  switch (m['k']) {
    case 'call':
      return BackendCall.fromMap(m);
    case 'reply':
      return BackendReply.fromMap(m);
    case 'event':
      return BackendEvent.fromMap(m);
    default:
      throw ArgumentError('Unknown message kind: ${m['k']}');
  }
}

// ── Request-id correlation ───────────────────────────────────────

/// Manages request IDs and pending call completions on the UI side.
class PendingCalls {
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  int get nextId => _nextId++;

  void register(int id, Completer<Map<String, dynamic>> completer) {
    _pending[id] = completer;
  }

  /// Resolves the pending call with [reply]. Returns true if a matching
  /// pending call was found.
  bool resolve(BackendReply reply) {
    final completer = _pending.remove(reply.id);
    if (completer == null) return false;
    if (reply.ok) {
      completer.complete(reply.result ?? {});
    } else {
      completer.completeError(
        reply.error ?? const BackendError(code: 'unknown', message: 'No error details'),
      );
    }
    return true;
  }

  /// Rejects all pending calls (e.g. on worker shutdown).
  void rejectAll(Object error) {
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }

  int get pendingCount => _pending.length;
}

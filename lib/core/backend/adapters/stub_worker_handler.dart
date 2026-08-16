// coverage:ignore-file

import 'package:kohera/core/backend/transport/protocol.dart';
import 'package:kohera/core/backend/ports/worker_handler.dart';

// ── StubWorkerHandler ─────────────────────────────────────────────
//
// A no-op handler that returns empty data for the rooms-list capability.
// Exercises the full isolate transport end-to-end without the matrix SDK.
// Mirrors the shape of InProcessBackend so the UI proxy can't tell the
// difference.

class StubWorkerHandler implements WorkerHandler {
  @override
  Future<BackendResult> handle(BackendCall call, EmitEvent emit) async {
    switch (call.op) {
      case 'accounts.list':
        return const BackendResult.ok({'accounts': <Map<String, dynamic>>[]});
      case 'rooms.list':
        return const BackendResult.ok({'rooms': <Map<String, dynamic>>[]});
      case 'timeline.fetch':
      case 'timeline.paginate':
        return const BackendResult.ok({'events': <Map<String, dynamic>>[]});
      case 'subscribe.timeline.newEvents':
        return const BackendResult.ok({});
      default:
        return BackendResult.error(
          BackendError(code: 'unknown_op', message: 'Unknown op: ${call.op}'),
        );
    }
  }

  @override
  Future<void> dispose() async {}
}

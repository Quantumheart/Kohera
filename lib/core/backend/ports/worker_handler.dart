// coverage:ignore-file

import 'package:kohera/core/backend/transport/protocol.dart';

// ── WorkerHandler ─────────────────────────────────────────────────
//
// The worker-isolate dispatch target.  The worker entry point decodes each
// incoming [BackendCall], hands it to `handle`, and encodes the returned
// [BackendResult] as a [BackendReply] back to the UI.
//
// When the handler wants to push an unsolicited stream event to the UI, it
// calls [emit] with a [BackendEvent].
//
// Implementations:
//   - StubWorkerHandler (this issue — empty data, no events)
//   - MatrixSdkWorkerHandler (issue #3 — runs the real SDK on the worker)

/// The result of handling a [BackendCall].  Either a success [Map] or a
/// [BackendError].
class BackendResult {
  final bool ok;
  final Map<String, dynamic>? data;
  final BackendError? error;

  const BackendResult.ok(this.data)
      : ok = true,
        error = null;

  const BackendResult.error(this.error)
      : ok = false,
        data = null;
}

/// Emitted by the handler to push a stream event to the UI.
typedef EmitEvent = void Function(BackendEvent event);

abstract class WorkerHandler {
  /// Handles a [BackendCall] from the UI.  Return a [BackendResult] that the
  /// worker entry point will encode as a [BackendReply].  Call [emit] to push
  /// unsolicited [BackendEvent]s to the UI (for streams like `roomListUpdates`).
  Future<BackendResult> handle(BackendCall call, EmitEvent emit);

  /// Called when the worker is shutting down.  Clean up resources.
  Future<void> dispose();
}

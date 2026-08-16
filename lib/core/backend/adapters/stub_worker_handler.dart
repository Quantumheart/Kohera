// coverage:ignore-file

import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/protocol.dart';

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
      case 'roomMgmt.leave':
      case 'roomMgmt.join':
      case 'roomMgmt.invite':
      case 'roomMgmt.kick':
      case 'roomMgmt.ban':
      case 'roomMgmt.unban':
      case 'roomMgmt.setName':
      case 'roomMgmt.setTopic':
      case 'roomMgmt.setAvatar':
      case 'rooms.create':
      case 'roomState.set':
        return const BackendResult.ok({});
      case 'roomState.get':
        return const BackendResult.ok({'content': <String, dynamic>{}});
      case 'roomState.canChange':
        return const BackendResult.ok({'canChange': false});
      case 'roomState.getPowerLevel':
        return const BackendResult.ok({'powerLevel': 0});
      case 'members.get':
        return const BackendResult.ok({'members': <Map<String, dynamic>>[]});
      case 'members.getUser':
        return const BackendResult.ok({'user': <String, dynamic>{}});
      case 'members.search':
        return const BackendResult.ok({'users': <Map<String, dynamic>>[]});
      case 'message.send':
      case 'message.sendText':
      case 'message.react':
      case 'message.redact':
      case 'message.sendFile':
        return const BackendResult.ok({'eventId': null});
      case 'message.report':
      case 'read.setMarker':
      case 'read.setReceipt':
        return const BackendResult.ok({});
      case 'read.getReceipts':
        return const BackendResult.ok({'receipts': <String, dynamic>{}});
      default:
        return BackendResult.error(
          BackendError(code: 'unknown_op', message: 'Unknown op: ${call.op}'),
        );
    }
  }

  @override
  Future<void> dispose() async {}
}

// coverage:ignore-file

import 'package:kohera/core/backend/ports/worker_handler.dart';
import 'package:kohera/core/backend/transport/backend_ops.dart';
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
      case BackendOp.accountsList:
        return const BackendResult.ok({'accounts': <Map<String, dynamic>>[]});
      case BackendOp.roomsList:
        return const BackendResult.ok({'rooms': <Map<String, dynamic>>[]});
      case BackendOp.timelineFetch:
      case BackendOp.timelinePaginate:
        return const BackendResult.ok({'events': <Map<String, dynamic>>[]});
      case BackendOp.subscribeTimelineNewEvents:
        return const BackendResult.ok({});
      case BackendOp.roomMgmtLeave:
      case BackendOp.roomMgmtJoin:
      case BackendOp.roomMgmtInvite:
      case BackendOp.roomMgmtKick:
      case BackendOp.roomMgmtBan:
      case BackendOp.roomMgmtUnban:
      case BackendOp.roomMgmtSetName:
      case BackendOp.roomMgmtSetTopic:
      case BackendOp.roomMgmtSetAvatar:
      case BackendOp.roomsCreate:
      case BackendOp.roomStateSet:
        return const BackendResult.ok({});
      case BackendOp.roomStateGet:
        return const BackendResult.ok({'content': <String, dynamic>{}});
      case BackendOp.roomStateCanChange:
        return const BackendResult.ok({'canChange': false});
      case BackendOp.roomStateGetPowerLevel:
        return const BackendResult.ok({'powerLevel': 0});
      case BackendOp.membersGet:
        return const BackendResult.ok({'members': <Map<String, dynamic>>[]});
      case BackendOp.membersGetUser:
        return const BackendResult.ok({'user': <String, dynamic>{}});
      case BackendOp.membersSearch:
        return const BackendResult.ok({'users': <Map<String, dynamic>>[]});
      case BackendOp.messageSend:
      case BackendOp.messageSendText:
      case BackendOp.messageReact:
      case BackendOp.messageRedact:
      case BackendOp.messageSendFile:
        return const BackendResult.ok({'eventId': null});
      case BackendOp.messageReport:
      case BackendOp.readSetMarker:
      case BackendOp.readSetReceipt:
        return const BackendResult.ok({});
      case BackendOp.readGetReceipts:
        return const BackendResult.ok({'receipts': <String, dynamic>{}});
      case BackendOp.e2eeEncryptionEnabled:
        return const BackendResult.ok({'enabled': false});
      case BackendOp.e2eeDeviceKeys:
        return const BackendResult.ok({'devices': <Map<String, dynamic>>[]});
      case BackendOp.e2eeVerifyDevice:
      case BackendOp.e2eeCrossSigningSelfSign:
      case BackendOp.e2eeBootstrap:
      case BackendOp.subscribeE2eeKeyVerificationRequest:
        return const BackendResult.ok({});
      case BackendOp.e2eeStartVerification:
        return const BackendResult.ok({
          'verification': {'state': 'error', 'method': null, 'deviceId': null},
        });
      case BackendOp.e2eeCrossSigningEnabled:
        return const BackendResult.ok({'enabled': false});
      case BackendOp.e2eeCrossSigningIsCached:
        return const BackendResult.ok({'isCached': false});
      case BackendOp.e2eeKeyBackupUnlock:
        return const BackendResult.ok({'unlocked': false});
      case BackendOp.syncStatus:
        return const BackendResult.ok({'syncing': false});
      default:
        return BackendResult.error(
          BackendError(code: 'unknown_op', message: 'Unknown op: ${call.op}'),
        );
    }
  }

  @override
  Future<void> dispose() async {}
}

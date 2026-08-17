import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

const Set<String> callPreviewTypes = {
  EventTypes.CallInvite,
  EventTypes.CallAnswer,
  EventTypes.CallReject,
  EventTypes.CallHangup,
  EventTypes.GroupCallMember,
};

/// Sync filter used by every Kohera [Client].
///
/// The SDK default only lazy-loads member state and places **no limit** on the
/// room timeline, so an initial (or large incremental) `/sync` response can be
/// huge. The response body is `jsonDecode`d and then processed by `_handleSync`
/// on the **main isolate**, which blocks the UI thread long enough to trip the
/// OS "not responding" watchdog on desktop (see issue #991). Capping the
/// timeline to a small window keeps the sync payload small; the chat screen
/// paginates the rest on demand via `Timeline.requestHistory`.
final Filter koheraSyncFilter = Filter(
  room: RoomFilter(
    state: StateFilter(lazyLoadMembers: true),
    timeline: StateFilter(limit: 20),
  ),
);

Client buildClient(
  String clientName,
  MatrixSdkDatabase database,
  NativeImplementations nativeImplementations,
  Future<void> Function(Client)? onSoftLogout,
) {
  final client = Client(
    'Kohera ($clientName)',
    database: database,
    logLevel: kReleaseMode ? Level.warning : Level.verbose,
    defaultNetworkRequestTimeout: const Duration(minutes: 2),
    onSoftLogout: onSoftLogout,
    verificationMethods: {
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
      KeyVerificationMethod.qrShow,
      KeyVerificationMethod.qrScan,
    },
    enableDehydratedDevices: true,
    enableLatexMarkdown: false,
    nativeImplementations: nativeImplementations,
    syncFilter: koheraSyncFilter,
  );
  client.roomPreviewLastEvents.removeAll(callPreviewTypes);
  return client;
}

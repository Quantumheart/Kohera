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

/// Whether to enable verbose Matrix SDK logging. Off by default because the
/// SDK's log path is a synchronous `print()` on the main isolate
/// (`Logs.printOut`). At `Level.verbose` the SDK logs per room/event during a
/// sync, and that unthrottled synchronous stdout flood starves the platform
/// event loop long enough to trip the OS "not responding" watchdog in debug
/// builds (see issue #991 — the app runs fine in profile, where
/// `kReleaseMode` is true and the level collapses to `warning`). Opt in with:
///   flutter run --dart-define=KOHERA_VERBOSE_SDK_LOGS=true
const bool _verboseSdkLogs = bool.fromEnvironment('KOHERA_VERBOSE_SDK_LOGS');

/// The SDK log level. Verbose only when explicitly opted in; otherwise
/// `Level.info` in debug (lifecycle logs, no per-event flood) and
/// `Level.warning` in profile/release (as before).
const Level koheraSdkLogLevel = _verboseSdkLogs
    ? Level.verbose
    : (kReleaseMode ? Level.warning : Level.info);

Client buildClient(
  String clientName,
  MatrixSdkDatabase database,
  NativeImplementations nativeImplementations,
  Future<void> Function(Client)? onSoftLogout,
) {
  final client = Client(
    'Kohera ($clientName)',
    database: database,
    logLevel: koheraSdkLogLevel,
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

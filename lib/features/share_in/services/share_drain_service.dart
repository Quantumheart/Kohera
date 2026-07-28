import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:kohera/features/share_in/models/pending_share.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:matrix/matrix.dart';

/// Resolves the Matrix [Client] that owns a share's target room.
///
/// Decouples [ShareDrainService] from `MatrixService` / `ClientManager` so the
/// drain can be tested with a mock [Client]. The main app wires this to
/// `clientManager.services` by `clientName`; the Share Extension writes the
/// owning account's `clientName` as `PendingShare.accountId`.
typedef ShareAccountResolver = Client? Function(String accountId);

/// Drains `pendingShares` staged by the iOS Share Extension and replays each
/// one as a Matrix send from the main app, where E2EE keys and the SDK live.
///
/// Drains run on launch (after the owning clients finish their initial room
/// load) and on `AppLifecycleState.resumed`, so a share staged while the app
/// is backgrounded is delivered as soon as the user returns. The drain is
/// idempotent: a per-process in-flight guard plus clear-on-success prevent
/// double-sends across overlapping drains.
///
/// Unrecoverable failures (account logged out, room left, staged file gone,
/// empty text) discard the entry with a log so the queue never blocks on a
/// share that can never succeed. Transient send errors (network, upload)
/// leave the entry in place to retry on the next drain.
class ShareDrainService with WidgetsBindingObserver {
  ShareDrainService({
    required ShareAccountResolver resolveClient,
    ShareInStore? store,
    Future<void> Function()? waitForClientsLoaded,
  })  : _resolveClient = resolveClient,
        _store = store ?? ShareInStore(),
        _waitForClientsLoaded = waitForClientsLoaded ?? _noWait;

  final ShareAccountResolver _resolveClient;
  final ShareInStore _store;
  final Future<void> Function() _waitForClientsLoaded;

  bool _draining = false;
  bool _disposed = false;
  final Set<String> _inFlight = {};

  static Future<void> _noWait() async {}

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(drainOnce());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(drainOnce());
    }
  }

  /// Drains the queue once. Safe to call concurrently; overlapping calls are
  /// coalesced by [_draining], and per-id in-flight tracking prevents a share
  /// from being sent twice in the same process.
  Future<void> drainOnce() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      await _waitForClientsLoaded();
      if (_disposed) return;
      final pending = await _store.readPendingShares();
      if (pending.isEmpty) return;

      final drained = <String>{};
      for (final share in pending) {
        if (_disposed) break;
        if (!drained.add(share.id)) continue;
        if (_inFlight.contains(share.id)) continue;
        _inFlight.add(share.id);
        try {
          await _send(share);
          await _store.clearPendingShare(share.id);
        } catch (e) {
          debugPrint(
            '[Kohera] Share drain send failed for ${share.id}, will retry: $e',
          );
        } finally {
          _inFlight.remove(share.id);
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _send(PendingShare share) async {
    final client = _resolveClient(share.accountId);
    if (client == null) {
      debugPrint(
        '[Kohera] Share drain: account ${share.accountId} not found, '
        'discarding ${share.id}',
      );
      return;
    }
    final room = client.getRoomById(share.targetRoomId);
    if (room == null) {
      debugPrint(
        '[Kohera] Share drain: room ${share.targetRoomId} gone, '
        'discarding ${share.id}',
      );
      return;
    }
    switch (share.kind) {
      case PendingShareKind.text:
        final text = share.text;
        if (text == null || text.isEmpty) {
          debugPrint(
            '[Kohera] Share drain: empty text, discarding ${share.id}',
          );
          return;
        }
        await room.sendTextEvent(text);
      case PendingShareKind.file:
        final path = share.filePath;
        if (path == null || !File(path).existsSync()) {
          debugPrint(
            '[Kohera] Share drain: staged file missing, discarding ${share.id}',
          );
          return;
        }
        final bytes = await File(path).readAsBytes();
        final name = share.originalFileName ?? path.split('/').last;
        final file = MatrixFile.fromMimeType(bytes: bytes, name: name);
        await room.sendFileEvent(file);
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }
}

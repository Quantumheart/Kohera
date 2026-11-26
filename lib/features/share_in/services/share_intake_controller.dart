import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/share_in/models/incoming_share.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';

/// Receives the single [IncomingShare] the iOS Share Extension staged and
/// sends it to the chosen room via the active account (which lives in the
/// main app, with E2EE keys), then navigates to that room. The extension
/// only stages the content + picked room and redirects to the host app via
/// the `koherashare://` URL scheme; this controller wakes on `resumed` /
/// launch, reads the one-shot record, sends, and clears it.
///
/// There is no queue: the record is cleared as soon as it is read, and the
/// captured share is sent from the send closure.
class ShareIntakeController with WidgetsBindingObserver {
  ShareIntakeController({
    required RoomRepository rooms,
    required GoRouter Function() router,
    ShareInStore? store,
  })  : _rooms = rooms,
        _router = router,
        _store = store ?? ShareInStore();

  final RoomRepository _rooms;

  /// Resolves the active router. The composition root rebuilds the router on
  /// account switch, so this is read at call time rather than captured.
  final GoRouter Function() _router;
  final ShareInStore _store;
  bool _handling = false;
  bool _disposed = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_handle(waitForLoad: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handle(waitForLoad: false));
    }
  }

  Future<void> _handle({required bool waitForLoad}) async {
    if (_handling || _disposed) return;
    _handling = true;
    try {
      if (waitForLoad) {
        try {
          await _rooms.roomsLoaded;
        } catch (e) {
          debugPrint('[Kohera] Share intake roomsLoading wait failed: $e');
        }
      }
      if (_disposed) return;
      final share = await _store.readIncomingShare();
      if (share == null || share.isEmpty) return;
      // One-shot: clear now so a later resume doesn't re-send; the captured
      // share is sent below.
      await _store.clearIncomingShare();

      await sendIncomingShareToRoom(_rooms, share.roomId, share);
      final displayname =
          _rooms.summaryFor(share.roomId)?.displayname ?? share.roomId;
      await _store.donateSendMessage(roomId: share.roomId, displayname: displayname);
      _router().go('${RoutePaths.roomPrefix}${share.roomId}');
    } catch (e) {
      debugPrint('[Kohera] Share intake failed: $e');
    } finally {
      _handling = false;
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Sends an [IncomingShare] (text + files) to [share.roomId] via [rooms].
/// Throws on failure so a caller can surface the error. Staged file payloads
/// that are missing on disk are skipped with a log.
Future<void> sendIncomingShareToRoom(
  RoomRepository rooms,
  String roomId,
  IncomingShare share,
) async {
  if (!rooms.roomExists(roomId)) {
    throw StateError('Room $roomId not found');
  }
  final text = share.text;
  if (text != null && text.isNotEmpty) {
    await rooms.sendText(roomId, text);
  }
  for (final file in share.files) {
    final path = file.filePath;
    if (!File(path).existsSync()) {
      debugPrint('[Kohera] Share intake: staged file missing, skipping $path');
      continue;
    }
    final bytes = await File(path).readAsBytes();
    await rooms.sendFile(roomId, bytes, file.name);
  }
}

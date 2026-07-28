import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/features/share_in/models/incoming_share.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:matrix/matrix.dart';

/// Receives the single [IncomingShare] the iOS Share Extension staged and
/// sends it to the chosen room via the Matrix SDK (which lives in the main
/// app, with E2EE keys), then navigates to that room. The extension only
/// stages the content + picked room and redirects to the host app via the
/// `koherashare://` URL scheme; this controller wakes on `resumed` / launch,
/// reads the one-shot record, sends, and clears it.
///
/// There is no queue: the record is cleared as soon as it is read, and the
/// captured share is sent from the send closure.
class ShareIntakeController with WidgetsBindingObserver {
  ShareIntakeController({
    required ClientManager clientManager,
    required GoRouter router,
    ShareInStore? store,
  })  : _clientManager = clientManager,
        _router = router,
        _store = store ?? ShareInStore();

  final ClientManager _clientManager;
  final GoRouter _router;
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
          await _clientManager.activeService.client.roomsLoading;
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

      final client = _clientManager.activeService.client;
      await sendIncomingShareToRoom(client, share.roomId, share);
      _router.go('${RoutePaths.roomPrefix}${share.roomId}');
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

/// Sends an [IncomingShare] (text + files) to [share.roomId] via [client].
/// Throws on failure so a caller can surface the error. Staged file payloads
/// that are missing on disk are skipped with a log.
Future<void> sendIncomingShareToRoom(
  Client client,
  String roomId,
  IncomingShare share,
) async {
  final room = client.getRoomById(roomId);
  if (room == null) {
    throw StateError('Room $roomId not found');
  }
  final text = share.text;
  if (text != null && text.isNotEmpty) {
    await room.sendTextEvent(text);
  }
  for (final file in share.files) {
    final path = file.filePath;
    if (!File(path).existsSync()) {
      debugPrint('[Kohera] Share intake: staged file missing, skipping $path');
      continue;
    }
    final bytes = await File(path).readAsBytes();
    final matrixFile = MatrixFile.fromMimeType(bytes: bytes, name: file.name);
    await room.sendFileEvent(matrixFile);
  }
}

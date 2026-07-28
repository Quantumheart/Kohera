import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/features/chat/widgets/forward_message_dialog.dart';
import 'package:kohera/features/share_in/models/incoming_share.dart';
import 'package:kohera/features/share_in/services/share_in_store.dart';
import 'package:kohera/shared/services/room_summary_resolver.dart';
import 'package:matrix/matrix.dart';

/// Receives the single [IncomingShare] the iOS Share Extension staged and
/// hands it to the in-app room picker for the user to choose a destination,
/// then sends it via the Matrix SDK (which lives in the main app, with E2EE
/// keys). The extension only stages the content and redirects to the host app
/// via the `koherashare://` URL scheme; this controller wakes on `resumed` /
/// launch, reads the one-shot record, shows the room picker, and sends.
///
/// There is no queue: the record is cleared as soon as it is read, and the
/// captured share is sent from the dialog's `onForward` closure.
class ShareIntakeController with WidgetsBindingObserver {
  ShareIntakeController({
    required ClientManager clientManager,
    required GlobalKey<NavigatorState> navKey,
    ShareInStore? store,
  })  : _clientManager = clientManager,
        _navKey = navKey,
        _store = store ?? ShareInStore();

  final ClientManager _clientManager;
  final GlobalKey<NavigatorState> _navKey;
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
      // One-shot: clear now so a later resume doesn't re-prompt; the captured
      // share is sent from the picker's onForward closure.
      await _store.clearIncomingShare();

      final service = _clientManager.activeService;
      final myUserId = service.client.userID;
      const resolver = RoomSummaryResolver();
      final targets = service.client.rooms
          .where((r) => r.membership == Membership.join && !r.isSpace)
          .map((r) => resolver(r, myUserId: myUserId))
          .toList();

      final context = _navKey.currentContext;
      if (context == null || !context.mounted) {
        debugPrint('[Kohera] Share intake: no navigator context, dropping share');
        return;
      }
      await ForwardMessageDialog.show(
        context,
        targets: targets,
        avatarResolver: service.avatarResolver,
        onForward: (roomId) =>
            sendIncomingShareToRoom(service.client, roomId, share),
      );
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

/// Sends an [IncomingShare] (text + files) to [roomId] via [client]. Throws on
/// failure so the room picker can surface the error and stay open for retry.
/// Staged file payloads that are missing on disk are skipped with a log.
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
    final matrixFile =
        MatrixFile.fromMimeType(bytes: bytes, name: file.name);
    await room.sendFileEvent(matrixFile);
  }
}

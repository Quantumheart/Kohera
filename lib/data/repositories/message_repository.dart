import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_media_content.dart';
import 'package:kohera/data/models/kohera_message_display.dart';
import 'package:kohera/data/models/kohera_poll.dart';
import 'package:kohera/data/models/kohera_reaction.dart';
import 'package:kohera/data/models/kohera_read_receipt.dart';
import 'package:kohera/data/models/kohera_reply_preview.dart';
import 'package:kohera/data/models/kohera_state_event_text.dart';
import 'package:kohera/data/resolvers/media_content_resolver.dart';
import 'package:kohera/data/resolvers/message_display_resolver.dart';
import 'package:kohera/data/resolvers/poll_resolver.dart';
import 'package:kohera/data/resolvers/reaction_resolver.dart';
import 'package:kohera/data/resolvers/read_receipt_resolver.dart';
import 'package:kohera/data/resolvers/reply_preview_resolver.dart';
import 'package:kohera/data/resolvers/state_event_resolver.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:matrix/matrix.dart';

class MessageRepository extends ChangeNotifier {
  MessageRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  // ── Domain model: message display ────────────────────────────

  KoheraMessageDisplay displayFor(Event event, {Timeline? timeline}) {
    return const MessageDisplayResolver()(event, timeline: timeline);
  }

  // ── Domain model: reactions ───────────────────────────────────

  KoheraReactionList reactionsFor(
    Event event,
    Timeline timeline, {
    required String myUserId,
  }) {
    return const ReactionResolver().resolve(
      event,
      timeline,
      myUserId: myUserId,
    );
  }

  // ── Domain model: reply preview ───────────────────────────────

  KoheraReplyPreview replyPreviewFromEvent(Event event) {
    return const ReplyPreviewResolver().fromEvent(event);
  }

  Future<KoheraReplyPreview?> resolveReplyParent(
    Event replyEvent,
    Timeline timeline,
  ) {
    return const ReplyPreviewResolver().resolveParent(replyEvent, timeline);
  }

  // ── Domain model: read receipts ──────────────────────────────

  Map<String, List<KoheraReadReceipt>> readReceiptsFor(
    Room room,
    String? myUserId, {
    String? threadRootId,
  }) {
    return const ReadReceiptResolver()(
      room,
      myUserId,
      threadRootId: threadRootId,
    );
  }

  // ── Domain model: state event text ────────────────────────────

  KoheraStateEventText stateEventTextFor(Event event) {
    return const StateEventResolver()(event);
  }

  // ── Domain model: media content ──────────────────────────────

  KoheraMediaContent mediaContentFor(Event event) {
    return const MediaContentResolver()(event);
  }

  // ── Domain model: poll ───────────────────────────────────────

  KoheraPoll? pollFor(
    Event event,
    Timeline timeline, {
    required String myUserId,
    required bool canRedact,
  }) {
    if (event.type != PollEventContent.startType) return null;
    return const PollResolver()(
      event,
      timeline,
      myUserId: myUserId,
      canRedact: canRedact,
    );
  }

  // ── Timeline access (transitional) ───────────────────────────

  Future<Timeline?> timelineFor(String roomId) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room == null) return null;
    return room.getTimeline();
  }

  // ── Message search ───────────────────────────────────────────

  MessageIndexerService? get messageIndexer => _matrix.messageIndexer;

  Future<void> ensureRoomIndexed(Room room) async {
    await _matrix.messageIndexer?.ensureRoomIndexed(room);
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}

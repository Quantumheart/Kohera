import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

class MessageRepository extends ChangeNotifier {
  MessageRepository({
    required MatrixClientService clientService,
    required String clientName,
    MessageIndexerService? indexerOverride,
  })  : _clientService = clientService,
        _indexer = indexerOverride ??
            MessageIndexerService(
              matrixClientService: clientService,
              clientName: clientName,
            ) {
    _indexer.addListener(_onIndexerChanged);
  }

  final MatrixClientService _clientService;
  final MessageIndexerService _indexer;
  bool _disposed = false;

  Client get _client => _clientService.client;

  void _onIndexerChanged() {
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
    return ReactionResolver.resolve(
      event,
      timeline,
      myUserId: myUserId,
    );
  }

  // ── Domain model: reply preview ───────────────────────────────

  KoheraReplyPreview replyPreviewFromEvent(Event event) {
    return ReplyPreviewResolver.fromEvent(event);
  }

  Future<KoheraReplyPreview?> resolveReplyParent(
    Event replyEvent,
    Timeline timeline,
  ) {
    return ReplyPreviewResolver.resolveParent(replyEvent, timeline);
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
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    return room.getTimeline();
  }

  // ── Message search ───────────────────────────────────────────

  /// Starts the local search index (subscribes to sync; no backfill yet).
  Future<void> initSearchIndex() => _indexer.init();

  /// Ensures [room]'s history is indexed for local search (background).
  Future<void> ensureRoomIndexed(Room room) => _indexer.ensureRoomIndexed(room);

  /// `true` while any room's search backfill is in progress.
  bool get isIndexing => _indexer.isIndexing;

  /// Search-index backfill progress for [roomId], or null if not indexing.
  int? indexingProgressFor(String roomId) =>
      _indexer.indexingProgressFor(roomId);

  /// The FTS5 search index, for the local-search query path.
  MessageSearchDatabase get searchDatabase => _indexer.database;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _indexer.removeListener(_onIndexerChanged);
    _indexer.dispose();
    super.dispose();
  }
}

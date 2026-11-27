import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_media_content.dart';
import 'package:kohera/data/models/kohera_message_display.dart';
import 'package:kohera/data/models/kohera_poll.dart';
import 'package:kohera/data/models/kohera_reaction.dart';
import 'package:kohera/data/models/kohera_read_receipt.dart';
import 'package:kohera/data/models/kohera_reply_preview.dart';
import 'package:kohera/data/models/kohera_state_event_text.dart';
import 'package:kohera/data/models/kohera_thread_children_page.dart';
import 'package:kohera/data/models/kohera_thread_summary.dart';
import 'package:kohera/data/models/kohera_timeline.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/data/resolvers/media_content_resolver.dart';
import 'package:kohera/data/resolvers/message_display_resolver.dart';
import 'package:kohera/data/resolvers/poll_resolver.dart';
import 'package:kohera/data/resolvers/reaction_resolver.dart';
import 'package:kohera/data/resolvers/read_receipt_resolver.dart';
import 'package:kohera/data/resolvers/reply_preview_resolver.dart';
import 'package:kohera/data/resolvers/state_event_resolver.dart';
import 'package:kohera/data/resolvers/timeline_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:kohera/data/services/sdk_media_controller.dart';
import 'package:kohera/shared/services/media_controller.dart';
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

  // ── Domain model: timeline ──────────────────────────────────

  /// Returns a domain timeline for [roomId], optionally rooted at
  /// [eventContextId] (a fragmented context view).
  ///
  /// The returned [KoheraTimeline] owns its SDK subscriptions; callers
  /// must dispose it.
  Future<KoheraTimeline?> getTimeline(
    String roomId, {
    String? eventContextId,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    const resolver = TimelineResolver();
    final myUserId = _client.userID;
    late KoheraTimeline koheraTimeline;
    late Timeline sdkTimeline;
    sdkTimeline = await room.getTimeline(
      eventContextId: eventContextId,
      onUpdate: () => koheraTimeline.publish(
        resolver.convertTimeline(sdkTimeline, myUserId: myUserId),
      ),
    );
    return koheraTimeline = KoheraTimeline(
      roomId: roomId,
      events: resolver.convertTimeline(sdkTimeline, myUserId: myUserId),
      canRequestHistory: () => sdkTimeline.canRequestHistory,
      isFragmented: () => !sdkTimeline.allowNewEvent,
      requestHistory: sdkTimeline.requestHistory,
      onDispose: sdkTimeline.cancelSubscriptions,
    );
  }

  // ── Domain model: thread summaries ──────────────────────────

  /// Fetches thread roots for [roomId] from the server, with each root's
  /// replies, decrypted where possible, as domain summaries.
  ///
  /// Returns an empty list when the room is unknown locally.
  Future<List<KoheraThreadSummary>> fetchThreadSummaries(
    String roomId, {
    int limit = 50,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return const [];
    final myUserId = _client.userID ?? '';
    final response = await _client.getThreadRoots(room.id, limit: limit);

    final summaries = <KoheraThreadSummary>[];
    for (final raw in response.chunk) {
      final root = await _decryptIfNeeded(
        Event.fromMatrixEvent(raw, room),
      );
      final children = await _fetchThreadChildren(room, root.eventId);
      final lastReply = children.isEmpty ? null : children.last;
      summaries.add(
        KoheraThreadSummary(
          rootEventId: root.eventId,
          rootBody: root.body,
          rootRedacted: root.redacted,
          rootTimestamp: root.originServerTs,
          replyCount: children.length,
          unreadCount: _threadUnreadCount(
            room: room,
            rootEventId: root.eventId,
            children: children,
            myUserId: myUserId,
          ),
          lastActivity: lastReply?.originServerTs ?? root.originServerTs,
          lastReplySenderName: lastReply == null
              ? null
              : lastReply.senderFromMemoryOrFallback.displayName ??
                  lastReply.senderId,
          lastReplyBody: lastReply?.body,
          lastReplyRedacted: lastReply?.redacted ?? false,
        ),
      );
    }
    summaries.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return summaries;
  }

  Future<List<Event>> _fetchThreadChildren(Room room, String rootEventId) async {
    final relations = await _client.getRelatingEventsWithRelType(
      room.id,
      rootEventId,
      RelationshipTypes.thread,
      limit: 100,
    );
    final events = <Event>[];
    for (final raw in relations.chunk) {
      events.add(await _decryptIfNeeded(Event.fromMatrixEvent(raw, room)));
    }
    events.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    return events;
  }

  Future<Event> _decryptIfNeeded(Event event) async {
    if (event.type != EventTypes.Encrypted) return event;
    final encryption = _client.encryption;
    if (encryption == null) return event;
    try {
      final decrypted = await encryption
          .decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      return decrypted;
    } catch (_) {
      return event;
    }
  }

  static int _threadUnreadCount({
    required Room room,
    required String rootEventId,
    required List<Event> children,
    required String myUserId,
  }) {
    final receipt = room.receiptState.byThread[rootEventId]?.latestOwnReceipt;
    final receiptTs = receipt?.ts ?? 0;
    var count = 0;
    for (final child in children) {
      if (child.senderId == myUserId) continue;
      if (child.originServerTs.millisecondsSinceEpoch > receiptTs) count++;
    }
    return count;
  }

  // ── Forwarding ──────────────────────────────────────────────

  /// Forwards [sourceEventId] from [sourceRoomId] to [targetRoomId].
  ///
  /// The latest edited version is forwarded; relation metadata
  /// (`m.relates_to`, `m.new_content`) is stripped so the copy is a
  /// standalone message. Media is forwarded by reference — the original
  /// `mxc://` URI (and, for encrypted rooms, the embedded file key)
  /// travels in the content. No-op when a room or the event is unknown.
  Future<void> forwardMessage({
    required String targetRoomId,
    required String sourceRoomId,
    required String sourceEventId,
  }) async {
    final target = _client.getRoomById(targetRoomId);
    final sourceRoom = _client.getRoomById(sourceRoomId);
    if (target == null || sourceRoom == null) return;
    final timeline = await sourceRoom.getTimeline();
    Event? event;
    for (final e in timeline.events) {
      if (e.eventId == sourceEventId) {
        event = e;
        break;
      }
    }
    event ??= await sourceRoom.getEventById(sourceEventId);
    if (event == null) return;
    final source = event.getDisplayEvent(timeline);
    final content = Map<String, dynamic>.from(source.content)
      ..remove('m.relates_to')
      ..remove('m.new_content');
    await target.sendEvent(content, type: source.type);
  }

  // ── Timeline access (transitional) ───────────────────────────

  Future<Timeline?> timelineFor(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    return room.getTimeline();
  }

  // ── Timeline support ─────────────────────────────────────────

  /// Fetches [eventId] in [roomId] as a domain event, resolved against
  /// the room's live timeline. Returns null when the room or event is
  /// unknown.
  Future<KoheraTimelineEvent?> fetchEvent(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    final event = await room.getEventById(eventId);
    if (event == null) return null;
    final timeline = await room.getTimeline();
    return const TimelineResolver().convert(
      event,
      timeline: timeline,
      myUserId: _client.userID,
    );
  }

  /// Fetches one page of thread replies for [rootEventId] in [roomId],
  /// decrypted where possible, oldest first. Returns an empty page when
  /// the room is unknown.
  Future<KoheraThreadChildrenPage> fetchThreadChildrenPage(
    String roomId,
    String rootEventId, {
    String? from,
    int limit = 100,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return const KoheraThreadChildrenPage(events: []);
    final relations = await _client.getRelatingEventsWithRelType(
      room.id,
      rootEventId,
      RelationshipTypes.thread,
      limit: limit,
      from: from,
    );
    final events = <Event>[];
    for (final raw in relations.chunk) {
      events.add(await _decryptIfNeeded(Event.fromMatrixEvent(raw, room)));
    }
    events.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    final timeline = await room.getTimeline();
    final myUserId = _client.userID;
    const resolver = TimelineResolver();
    return KoheraThreadChildrenPage(
      events: events
          .map(
            (e) => resolver.convert(e, timeline: timeline, myUserId: myUserId),
          )
          .toList(growable: false),
      nextBatch: relations.nextBatch,
    );
  }

  /// Builds a media controller for [eventId] in [roomId], or null when
  /// the room or event is unknown.
  Future<MediaController?> mediaControllerFor(
    String roomId,
    String eventId,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    final event = await room.getEventById(eventId);
    if (event == null) return null;
    return SdkMediaController(event, _client);
  }

  /// Pre-loads encryption group sessions for the recent history of
  /// [roomId] and decrypts what it can. No-op for unencrypted rooms or
  /// when no encryption engine is active.
  Future<void> preDecryptRoomHistory(String roomId) async {
    final room = _client.getRoomById(roomId);
    final encryption = _client.encryption;
    if (room == null || encryption == null || !room.encrypted) return;

    final events = await _client.database
        .getEventList(room, limit: Room.defaultHistoryCount);

    final sessionIds = <String>{};
    for (final event in events) {
      if (event.type == EventTypes.Encrypted) {
        final sessionId = event.content.tryGet<String>('session_id');
        if (sessionId != null) sessionIds.add(sessionId);
      }
    }
    for (final sessionId in sessionIds) {
      try {
        await encryption.keyManager
            .loadInboundGroupSession(room.id, sessionId);
      } catch (_) {}
    }

    for (final event in events) {
      if (event.type != EventTypes.Encrypted) continue;
      try {
        await encryption.decryptRoomEvent(
          event,
          store: !room.isArchived,
          updateType: EventUpdateType.history,
        );
      } catch (_) {}
    }
  }

  /// Requests missing inbound group session keys for undecryptable
  /// events on the live timeline of [roomId]. Fire-and-forget: failures
  /// are logged, not thrown.
  void requestMissingSessionKeys(String roomId) {
    final room = _client.getRoomById(roomId);
    final encryption = _client.encryption;
    if (room == null || encryption == null) return;

    unawaited(() async {
      final timeline = await room.getTimeline();
      final requested = <String>{};
      for (final event in timeline.events) {
        if (event.type != EventTypes.Encrypted ||
            event.messageType != MessageTypes.BadEncrypted) {
          continue;
        }
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId == null || !requested.add(sessionId)) continue;
        unawaited(
          encryption.keyManager.loadSingleKey(room.id, sessionId).catchError(
            (Object e) {
              debugPrint('[Kohera] Key load failed for $sessionId: $e');
            },
          ),
        );
        if (senderKey != null) {
          try {
            unawaited(
              Future.value(
                encryption.keyManager.maybeAutoRequest(
                  room.id,
                  sessionId,
                  senderKey,
                ),
              ),
            );
          } catch (e) {
            debugPrint('[Kohera] P2P key request failed for $sessionId: $e');
          }
        }
      }
    }());
  }

  // ── Message search ───────────────────────────────────────────

  /// Starts the local search index (subscribes to sync; no backfill yet).
  Future<void> initSearchIndex() => _indexer.init();

  /// Toggles [emoji] on the message [eventId] for the current user: redacts
  /// the existing matching reaction or sends a new one. No-op when the room
  /// or event is unknown.
  Future<void> toggleReaction(
    String roomId,
    String eventId,
    String emoji,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    final event = await room.getEventById(eventId);
    if (event == null) return;
    final timeline = await room.getTimeline();
    final myId = _client.userID;
    final existing = event
        .aggregatedEvents(timeline, RelationshipTypes.reaction)
        .where((e) =>
            e.senderId == myId &&
            e.content
                    .tryGetMap<String, Object?>('m.relates_to')
                    ?.tryGet<String>('key') ==
                emoji,)
        .firstOrNull;
    if (existing != null) {
      await existing.redactEvent();
    } else {
      await room.sendReaction(eventId, emoji);
    }
  }

  /// Returns the event ID of the newest thread reply under [rootEventId],
  /// or null when the thread has no replies or the root is unknown.
  Future<String?> latestThreadEventId(
    String roomId,
    String rootEventId,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    final event = await room.getEventById(rootEventId);
    if (event == null) return null;
    final timeline = await room.getTimeline();
    final children = event.aggregatedEvents(timeline, RelationshipTypes.thread);
    if (children.isEmpty) return null;
    return children
        .reduce((a, b) => a.originServerTs.isAfter(b.originServerTs) ? a : b)
        .eventId;
  }

  /// Sends [text] to [roomId] with optional reply, edit, and thread
  /// relations. Returns the sent event ID, or null when the room is unknown.
  Future<String?> sendText(
    String roomId,
    String text, {
    String? inReplyToEventId,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    Event? replyEvent;
    if (editEventId == null && inReplyToEventId != null) {
      replyEvent = await room.getEventById(inReplyToEventId);
    }
    return room.sendTextEvent(
      text,
      inReplyTo: replyEvent,
      editEventId: editEventId,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
    );
  }

  /// Starts an MSC3381 poll in [roomId] from the given answer labels.
  Future<void> startPoll(
    String roomId, {
    required String question,
    required List<String> answers,
    required bool disclosed,
    int maxSelections = 1,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    final pollAnswers = answers
        .map(
          (label) => PollAnswer(
            id: _client.generateUniqueTransactionId(),
            mText: label,
          ),
        )
        .toList(growable: false);
    await room.startPoll(
      question: question,
      answers: pollAnswers,
      kind: disclosed ? PollKind.disclosed : PollKind.undisclosed,
      maxSelections: maxSelections,
    );
  }

  /// Votes [answerIds] on the poll whose start event is [eventId].
  Future<void> answerPoll(
    String roomId,
    String eventId,
    List<String> answerIds,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    final event = await room.getEventById(eventId);
    if (event == null) {
      debugPrint('[Kohera] Poll start event not found: $eventId');
      return;
    }
    await event.answerPoll(answerIds);
  }

  /// Ends the MSC3381 poll whose start event is [eventId].
  ///
  /// The SDK (`Event.endPoll`) enforces that only the poll creator or a user
  /// with redact power may end the poll; the UI gates the action upstream
  /// via `KoheraPoll.canEnd`, so no extra permission check is needed here.
  Future<void> endPoll(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    final event = await room.getEventById(eventId);
    if (event == null) {
      debugPrint('[Kohera] Poll start event not found: $eventId');
      return;
    }
    await event.endPoll();
  }

  /// Ensures [roomId]'s history is indexed for local search (background).
  Future<void> ensureRoomIndexed(String roomId, {bool priority = false}) {
    final room = _client.getRoomById(roomId);
    if (room == null) return Future.value();
    return _indexer.ensureRoomIndexed(room, priority: priority);
  }

  /// `true` while any room's search backfill is in progress.
  bool get isIndexing => _indexer.isIndexing;

  /// Search-index backfill progress for [roomId], or null if not indexing.
  int? indexingProgressFor(String roomId) =>
      _indexer.indexingProgressFor(roomId);

  /// The FTS5 search index, for the local-search query path.
  SearchIndex get searchDatabase => _indexer.database;

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

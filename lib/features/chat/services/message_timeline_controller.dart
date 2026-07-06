import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/models/chat_message_data.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/features/chat/models/kohera_state_event_text.dart';
import 'package:kohera/features/chat/services/media_content_resolver.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:kohera/features/chat/services/reaction_resolver.dart';
import 'package:kohera/features/chat/services/read_receipt_resolver.dart';
import 'package:kohera/features/chat/services/sdk_media_controller.dart';
import 'package:kohera/features/chat/services/state_event_resolver.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/shared/models/call_constants.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:matrix/matrix.dart';


/// Manages the Matrix timeline for a chat room and converts SDK [Event]s
/// into Kohera-owned domain models at the boundary.
///
/// This is the SDK conversion boundary for the chat message rendering path.
/// [MessageListView] and [ChatMessageItem] below it consume
/// [ChatMessageData] and never import `package:matrix/matrix.dart`.
class MessageTimelineController extends ChangeNotifier {
  MessageTimelineController({
    required this.matrix,
    required this.roomId,
    required this.sendPublicReadReceipts,
    this.initialEventId,
    this.threadRootEventId,
    List<Event>? extraEvents,
    this.onTimelineChanged,
  }) : _extraEvents = extraEvents;

  final MatrixService matrix;
  final String roomId;
  final bool sendPublicReadReceipts;
  final String? initialEventId;
  final String? threadRootEventId;
  List<Event>? _extraEvents;
  final VoidCallback? onTimelineChanged;

  static const _readMarkerDelay = Duration(seconds: 1);

  Room? _room;
  Timeline? _timeline;
  int _initGeneration = 0;
  bool _loadingHistory = false;
  Timer? _readMarkerTimer;
  String? _initialFullyReadId;
  List<ChatMessageData>? _cachedMessages;
  Map<String, List<KoheraReadReceipt>>? _cachedReceipts;
  bool _disposed = false;

  // ── State getters ──────────────────────────────────────

  bool get isReady => _timeline != null;
  bool get isThread => threadRootEventId != null;
  bool get isLoadingHistory => _loadingHistory;
  String? get fullyReadMarkerId => _initialFullyReadId;

  Timeline? get timeline => _timeline;
  Room? get room => _room;

  String? get myUserId => matrix.client.userID;

  List<ChatMessageData> get messages {
    if (_cachedMessages != null) return _cachedMessages!;
    final timelineEvents = _timeline?.events;
    if (timelineEvents == null) return [];
    final visible = buildVisibleEvents(
      timelineEvents,
      extraEvents: _extraEvents,
      threadRootId: threadRootEventId,
    );
    _cachedMessages = _buildMessageData(visible);
    return _cachedMessages!;
  }

  int get messageCount => messages.length;

  Map<String, List<KoheraReadReceipt>> get receipts {
    if (_cachedReceipts != null) return _cachedReceipts!;
    final room = _room;
    final uid = myUserId;
    if (room == null || uid == null) {
      _cachedReceipts = {};
      return _cachedReceipts!;
    }
    _cachedReceipts = const ReadReceiptResolver()(
      room,
      uid,
      threadRootId: threadRootEventId,
    );
    return _cachedReceipts!;
  }

  // ── Temporary SDK access for action resolution ──────────

  Event? getEventById(String eventId) {
    final timelineEvents = _timeline?.events;
    if (timelineEvents != null) {
      for (final e in timelineEvents) {
        if (e.eventId == eventId) return e;
      }
    }
    if (_extraEvents != null) {
      for (final e in _extraEvents!) {
        if (e.eventId == eventId) return e;
      }
    }
    return null;
  }

  int indexOf(String eventId) =>
      messages.indexWhere((m) => m.eventId == eventId);

  /// Updates the extra events list (used by thread screen for reply pagination).
  void updateExtraEvents(List<Event>? events) {
    _extraEvents = events;
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();
  }

  // ── Lifecycle ──────────────────────────────────────────

  Future<void> init() async {
    _room = matrix.client.getRoomById(roomId);
    if (_room == null) return;
    await _initTimeline();
  }

  Future<void> _initTimeline() async {
    final room = _room!;
    final gen = ++_initGeneration;
    final snapshotFullyRead = room.fullyRead;
    _initialFullyReadId =
        snapshotFullyRead.isNotEmpty ? snapshotFullyRead : null;
    _timeline = await room.getTimeline(
      eventContextId: initialEventId,
      onUpdate: () {
        if (_disposed) return;
        _cachedMessages = null;
        _cachedReceipts = null;
        notifyListeners();
        onTimelineChanged?.call();
        _markAsRead();
      },
    );
    if (gen != _initGeneration || _disposed) return;
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();
    onTimelineChanged?.call();
    _markAsRead();
    _requestMissingKeys();
    await _autoPaginateUntilVisible(gen);
  }

  Future<void> _autoPaginateUntilVisible(int gen) async {
    const maxRounds = 5;
    var rounds = 0;
    while (!_disposed &&
        gen == _initGeneration &&
        messages.isEmpty &&
        (_timeline?.events.isNotEmpty ?? false) &&
        (_timeline?.canRequestHistory ?? false) &&
        rounds < maxRounds) {
      rounds++;
      await _requestHistoryBatch();
    }
  }

  void _requestMissingKeys() {
    final room = _room;
    if (room == null) return;
    final encryption = room.client.encryption;
    if (encryption == null) return;

    final events = _timeline?.events;
    if (events == null) return;

    final requested = <String>{};
    for (final event in events) {
      if (event.type == EventTypes.Encrypted &&
          event.messageType == MessageTypes.BadEncrypted) {
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId != null && requested.add(sessionId)) {
          unawaited(
            encryption.keyManager.loadSingleKey(room.id, sessionId).catchError(
              (Object e) {
                debugPrint('[Kohera] Key load failed for $sessionId: $e');
              },
            ),
          );
          if (senderKey != null) {
            try {
              unawaited(Future.value(encryption.keyManager.maybeAutoRequest(
                room.id,
                sessionId,
                senderKey,
              )));
            } catch (e) {
              debugPrint('[Kohera] P2P key request failed for $sessionId: $e');
            }
          }
        }
      }
    }
  }

  // ── Pagination ─────────────────────────────────────────

  bool get canRequestHistory =>
      _timeline != null && _timeline!.canRequestHistory;

  Future<void> _requestHistoryBatch() async {
    if (_timeline == null || !_timeline!.canRequestHistory) return;
    await _timeline!.requestHistory();
    _cachedMessages = null;
    _cachedReceipts = null;
  }

  /// Loads history in a loop until [shouldContinue] returns false.
  /// The widget provides [shouldContinue] based on scroll position.
  Future<void> loadMore({required bool Function() shouldContinue}) async {
    if (threadRootEventId != null) return;
    if (_timeline == null || !_timeline!.canRequestHistory || _loadingHistory) {
      return;
    }
    _loadingHistory = true;
    notifyListeners();
    try {
      while (!_disposed && _timeline!.canRequestHistory) {
        await _requestHistoryBatch();
        notifyListeners();
        if (!shouldContinue()) break;
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to load history: $e');
    } finally {
      _loadingHistory = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ── Read marker ────────────────────────────────────────

  void _markAsRead() {
    _readMarkerTimer?.cancel();
    _readMarkerTimer = Timer(_readMarkerDelay, () async {
      if (_disposed) return;
      final room = _room;
      if (room == null) return;
      final client = matrix.client;
      final threadRootId = threadRootEventId;

      if (threadRootId != null) {
        final visible = messages;
        if (visible.isEmpty) return;
        final lastThreadEvent = visible.first;
        try {
          await client.postReceipt(
            room.id,
            ReceiptType.mRead,
            lastThreadEvent.eventId,
            threadId: threadRootId,
          );
        } catch (e) {
          debugPrint('[Kohera] Failed to mark thread as read: $e');
        }
        return;
      }

      if (room.notificationCount == 0) return;
      final visible = messages;
      final lastMainEvent = visible.isNotEmpty ? visible.first : null;
      if (lastMainEvent == null) return;
      try {
        await room.setReadMarker(
          lastMainEvent.eventId,
          mRead: sendPublicReadReceipts ? lastMainEvent.eventId : null,
        );
        await client.postReceipt(
          room.id,
          ReceiptType.mRead,
          lastMainEvent.eventId,
          threadId: 'main',
        );
      } catch (e) {
        debugPrint('[Kohera] Failed to mark as read: $e');
      }
    });
  }

  // ── Navigation ─────────────────────────────────────────

  Future<void> reloadTimelineAt(String eventId) async {
    final room = _room;
    if (room == null) return;
    _timeline?.cancelSubscriptions();
    _cachedMessages = null;
    _cachedReceipts = null;
    _timeline = null;
    notifyListeners();

    final gen = ++_initGeneration;
    _timeline = await room.getTimeline(
      eventContextId: eventId,
      onUpdate: () {
        if (_disposed) return;
        _cachedMessages = null;
        _cachedReceipts = null;
        notifyListeners();
        _markAsRead();
      },
    );
    if (gen != _initGeneration || _disposed) return;
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();
  }

  // ── Visible events filtering ───────────────────────────

  static List<Event> buildVisibleEvents(
    Iterable<Event> timelineEvents, {
    List<Event>? extraEvents,
    String? threadRootId,
  }) {
    final seen = <String>{};
    final merged = <Event>[];
    for (final e in timelineEvents) {
      if (seen.add(e.eventId)) merged.add(e);
    }
    if (extraEvents != null) {
      for (final e in extraEvents) {
        if (seen.add(e.eventId)) merged.add(e);
      }
    }
    return merged
        .where(
          (e) =>
              (((e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
                      e.relationshipType != RelationshipTypes.edit &&
                      !_isCallMemberEvent(e)) ||
                  callEventTypes.contains(e.type) ||
                  _isStateEvent(e) ||
                  e.type == EventTypes.Sticker) &&
              _matchesThread(e, threadRootId),
        )
        .toList()
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
  }

  static bool _matchesThread(Event event, String? threadRootId) {
    if (threadRootId == null) {
      return event.relationshipType != RelationshipTypes.thread;
    }
    if (event.eventId == threadRootId) return true;
    if (event.relationshipType != RelationshipTypes.thread) return false;
    return event.relationshipEventId == threadRootId;
  }

  static bool _isCallEvent(Event event) => callEventTypes.contains(event.type);

  static bool _isStateEvent(Event event) {
    if (event.type == EventTypes.RoomName ||
        event.type == EventTypes.RoomTopic ||
        event.type == EventTypes.RoomAvatar ||
        event.type == EventTypes.RoomTombstone) {
      return true;
    }
    if (event.type == EventTypes.RoomMember) {
      return !_isNoOpMemberEvent(event);
    }
    return false;
  }

  static bool _isNoOpMemberEvent(Event event) {
    final prev = event.prevContent;
    if (prev == null) return false;
    final curr = event.content;
    final prevMembership = prev.tryGet<String>('membership');
    final currMembership = curr.tryGet<String>('membership');
    if (prevMembership != currMembership) return false;
    if (prev.tryGet<String>('displayname') != curr.tryGet<String>('displayname')) {
      return false;
    }
    if (prev.tryGet<String>('avatar_url') != curr.tryGet<String>('avatar_url')) {
      return false;
    }
    return true;
  }

  static bool _isCallMemberEvent(Event event) =>
      event.type == kCallMember ||
      event.type == kCallMemberMsc ||
      event.body.contains(kCallMember) ||
      event.body.contains(kCallMemberMsc);

  Duration? _callDuration(Event event) {
    if (event.type != kCallHangup) return null;
    final reason = event.content.tryGet<String>('reason');
    if (reason == 'invite_timeout') return null;

    final hangupCallId = event.content.tryGet<String>('call_id');
    final events = _timeline?.events;
    if (events == null) return null;

    Event? matchedInvite;
    for (final e in events) {
      if (e.type != kCallInvite) continue;
      if (!e.originServerTs.isBefore(event.originServerTs)) continue;
      if (hangupCallId != null &&
          hangupCallId.isNotEmpty &&
          e.content.tryGet<String>('call_id') == hangupCallId) {
        matchedInvite = e;
        break;
      }
      matchedInvite ??= e;
    }

    if (matchedInvite == null) return null;
    final d = event.originServerTs.difference(matchedInvite.originServerTs);
    if (d.isNegative || d.inHours >= 24) return null;
    return d;
  }

  // ── ChatMessageData pre-computation ────────────────────

  List<ChatMessageData> _buildMessageData(List<Event> visible) {
    final uid = myUserId ?? '';
    final room = _room;
    final timeline = _timeline;
    final result = <ChatMessageData>[];

    for (var i = 0; i < visible.length; i++) {
      final event = visible[i];
      final isMe = event.senderId == uid;
      final prevSender = i + 1 < visible.length ? visible[i + 1].senderId : null;
      final isFirst = event.senderId != prevSender;

      final isPinned = room?.pinnedEventIds.contains(event.eventId) ?? false;
      final isRedacted = event.redacted;
      final canPin = !isRedacted &&
          (room?.canChangeStateEvent('m.room.pinned_events') ?? false);
      final canRedact = event.canRedact;

      final hasThread = timeline != null &&
          event.hasAggregatedEvents(timeline, RelationshipTypes.thread);
      final threadReplyCount = hasThread
          ? event.aggregatedEvents(timeline, RelationshipTypes.thread).length
          : 0;
      final threadUnreadCount = hasThread && room != null
          ? threadUnreadCountFor(
              root: event,
              timeline: timeline,
              room: room,
              myUserId: uid,
            )
          : 0;

      KoheraReactionList? reactions;
      if (timeline != null &&
          event.hasAggregatedEvents(timeline, RelationshipTypes.reaction)) {
        reactions = const ReactionResolver().resolve(
          event,
          timeline,
          myUserId: uid,
        );
      }

      final category = _classifyEvent(event);
      final message = const MessageDisplayResolver()(
        event,
        timeline: timeline,
      );

      KoheraStateEventText? stateEventText;
      KoheraMediaContent? media;
      MediaController? mediaController;
      Duration? callDuration;

      switch (category) {
        case MessageCategory.stateEvent:
          stateEventText = const StateEventResolver()(event);
        case MessageCategory.sticker:
          media = const MediaContentResolver()(event);
          mediaController = SdkMediaController(event);
        case MessageCategory.callEvent:
          callDuration = _callDuration(event);
        case MessageCategory.message:
          if (!isRedacted) {
            media = const MediaContentResolver()(event);
            mediaController = SdkMediaController(event);
          }
      }

      result.add(ChatMessageData(
        message: message,
        category: category,
        isMe: isMe,
        isFirst: isFirst,
        isPinned: isPinned,
        canPin: canPin,
        canRedact: canRedact,
        hasThread: hasThread,
        threadReplyCount: threadReplyCount,
        threadUnreadCount: threadUnreadCount,
        stateEventText: stateEventText,
        reactions: reactions,
        media: media,
        mediaController: mediaController,
        callDuration: callDuration,
      ),);
    }

    return result;
  }

  MessageCategory _classifyEvent(Event event) {
    if (_isCallEvent(event)) return MessageCategory.callEvent;
    if (_isStateEvent(event)) return MessageCategory.stateEvent;
    if (event.type == EventTypes.Sticker) return MessageCategory.sticker;
    return MessageCategory.message;
  }

  // ── Dispose ────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _readMarkerTimer?.cancel();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }
}

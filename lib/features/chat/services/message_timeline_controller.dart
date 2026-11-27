import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kohera/data/models/call_constants.dart';
import 'package:kohera/data/models/kohera_event_types.dart';
import 'package:kohera/data/models/kohera_message_display.dart';
import 'package:kohera/data/models/kohera_message_status.dart';
import 'package:kohera/data/models/kohera_read_receipt.dart';
import 'package:kohera/data/models/kohera_timeline.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/models/chat_message_data.dart';

/// Manages the domain timeline for a chat room and converts
/// [KoheraTimelineEvent] snapshots into [ChatMessageData] for rendering.
///
/// All SDK access lives behind [RoomRepository] and [MessageRepository];
/// this controller never imports `package:matrix/matrix.dart`.
/// [MessageListView] and [ChatMessageItem] below consume [ChatMessageData]
/// and never import the SDK either.
class MessageTimelineController extends ChangeNotifier
    with WidgetsBindingObserver {
  MessageTimelineController({
    required this.roomRepository,
    required this.messageRepository,
    required this.roomId,
    required this.sendPublicReadReceipts,
    this.initialEventId,
    this.threadRootEventId,
    List<KoheraTimelineEvent>? extraEvents,
    this.onTimelineChanged,
  }) : _extraEvents = extraEvents;

  final RoomRepository roomRepository;
  final MessageRepository messageRepository;
  final String roomId;
  final bool sendPublicReadReceipts;
  final String? initialEventId;
  final String? threadRootEventId;
  List<KoheraTimelineEvent>? _extraEvents;
  final VoidCallback? onTimelineChanged;

  static const _readMarkerDelay = Duration(seconds: 1);

  KoheraTimeline? _timeline;
  StreamSubscription<List<KoheraTimelineEvent>>? _eventsSub;
  int _initGeneration = 0;
  bool _loadingHistory = false;
  Timer? _readMarkerTimer;
  bool _readMarkerPending = false;
  bool _observingLifecycle = false;
  String? _initialFullyReadId;
  List<ChatMessageData>? _cachedMessages;
  Map<String, List<KoheraReadReceipt>>? _cachedReceipts;
  bool _disposed = false;

  /// Coalesces rapid-fire [KoheraTimeline.onEvents] emissions (e.g. during
  /// batch decryption or history pagination) into a single
  /// [notifyListeners] call on the next microtask. Without this, dozens of
  /// synchronous updates can trigger dozens of full message-list rebuilds
  /// in one frame, each creating and leaking gesture recognizers.
  bool _updateScheduled = false;

  /// Schedules a coalesced notification. Multiple calls within the same
  /// microtask are collapsed into one [notifyListeners] + [onTimelineChanged]
  /// + [_markAsRead] cycle.
  void _scheduleUpdate() {
    if (_disposed) return;
    _cachedMessages = null;
    _cachedReceipts = null;
    if (_updateScheduled) return;
    _updateScheduled = true;
    scheduleMicrotask(() {
      _updateScheduled = false;
      if (_disposed) return;
      notifyListeners();
      onTimelineChanged?.call();
      _markAsRead();
    });
  }

  // ── State getters ──────────────────────────────────────

  bool get isReady => _timeline != null;
  bool get isThread => threadRootEventId != null;
  bool get isLoadingHistory => _loadingHistory;
  String? get fullyReadMarkerId => _initialFullyReadId;

  /// `true` when the timeline is a fragmented context view (loaded via
  /// `eventContextId`) and cannot yet receive live sync events. A fragment is
  /// a peek: it never paginates forward on scroll. The UI shows a
  /// jump-to-latest affordance that reloads the live timeline instead.
  bool get isFragmented => _timeline?.isFragmented ?? false;

  String? get myUserId => roomRepository.userId;

  List<ChatMessageData> get messages {
    if (_cachedMessages != null) return _cachedMessages!;
    final timeline = _timeline;
    if (timeline == null) return const [];
    final visible = buildVisibleEvents(
      timeline.events,
      extraEvents: _extraEvents,
      threadRootId: threadRootEventId,
      ignoredUserIds: roomRepository.ignoredUsers,
    );
    _cachedMessages = _buildMessageData(visible);
    return _cachedMessages!;
  }

  int get messageCount => messages.length;

  Map<String, List<KoheraReadReceipt>> get receipts {
    if (_cachedReceipts != null) return _cachedReceipts!;
    if (myUserId == null) {
      _cachedReceipts = const {};
      return _cachedReceipts!;
    }
    _cachedReceipts = roomRepository.readReceipts(
      roomId,
      threadRootId: threadRootEventId,
    );
    return _cachedReceipts!;
  }

  // ── Event lookup ───────────────────────────────────────

  KoheraTimelineEvent? getEventById(String eventId) {
    final found = _timeline?.eventById(eventId);
    if (found != null) return found;
    if (_extraEvents != null) {
      for (final e in _extraEvents!) {
        if (e.eventId == eventId) return e;
      }
    }
    return null;
  }

  int indexOf(String eventId) =>
      messages.indexWhere((m) => m.eventId == eventId);

  /// Updates the extra events list (used by thread screen for reply
  /// pagination).
  void updateExtraEvents(List<KoheraTimelineEvent>? events) {
    _extraEvents = events;
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();
  }

  // ── Lifecycle ──────────────────────────────────────────

  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    if (!roomRepository.roomExists(roomId)) {
      _initFuture = null;
      return;
    }
    try {
      await _initTimeline();
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<void> _initTimeline() async {
    final gen = ++_initGeneration;
    _initialFullyReadId = roomRepository.fullyReadMarkerId(roomId);
    try {
      if (initialEventId == null) {
        await messageRepository.preDecryptRoomHistory(roomId);
      }
    } catch (_) {}
    if (gen != _initGeneration || _disposed) return;
    final timeline = await messageRepository.getTimeline(
      roomId,
      eventContextId: initialEventId,
    );
    if (gen != _initGeneration || _disposed || timeline == null) {
      timeline?.dispose();
      return;
    }
    _attachTimeline(timeline);
    _markAsRead();
    messageRepository.requestMissingSessionKeys(roomId);
    await _autoPaginateUntilVisible(gen);
  }

  void _attachTimeline(KoheraTimeline timeline) {
    unawaited(_eventsSub?.cancel());
    _timeline?.dispose();
    _timeline = timeline;
    _eventsSub = timeline.onEvents.listen((_) => _scheduleUpdate());
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();
    onTimelineChanged?.call();
  }

  void _detachTimeline() {
    unawaited(_eventsSub?.cancel());
    _eventsSub = null;
    final timeline = _timeline;
    _timeline = null;
    timeline?.dispose();
  }

  Future<void> _autoPaginateUntilVisible(int gen) async {
    const maxRounds = 5;
    var rounds = 0;
    while (!_disposed &&
        gen == _initGeneration &&
        messages.isEmpty &&
        (_timeline?.events.isNotEmpty ?? false) &&
        canRequestHistory &&
        rounds < maxRounds) {
      rounds++;
      await _requestHistoryBatch();
    }
  }

  // ── Pagination ─────────────────────────────────────────

  bool get canRequestHistory => _timeline?.canRequestHistory ?? false;

  Future<void> _requestHistoryBatch() async {
    final timeline = _timeline;
    if (timeline == null || !timeline.canRequestHistory) return;
    await timeline.requestHistory();
    _cachedMessages = null;
    _cachedReceipts = null;
  }

  /// Loads history in a loop until [shouldContinue] returns false.
  /// The widget provides [shouldContinue] based on scroll position.
  Future<void> loadMore({required bool Function() shouldContinue}) async {
    if (threadRootEventId != null) return;
    final timeline = _timeline;
    if (timeline == null || !timeline.canRequestHistory || _loadingHistory) {
      return;
    }
    _loadingHistory = true;
    notifyListeners();
    try {
      while (!_disposed && timeline.canRequestHistory) {
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

  // ── Read marker ──────────────────────────────────────────

  bool get _isAppInForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_readMarkerPending) return;
    _readMarkerPending = false;
    _markAsRead();
  }

  void _markAsRead() {
    _readMarkerTimer?.cancel();
    _readMarkerTimer = Timer(_readMarkerDelay, () async {
      if (_disposed) return;
      if (!_isAppInForeground) {
        _readMarkerPending = true;
        return;
      }
      final threadRootId = threadRootEventId;

      if (threadRootId != null) {
        final visible = messages;
        if (visible.isEmpty) return;
        final lastThreadEvent = visible.first;
        try {
          await roomRepository.markThreadRead(
            roomId,
            lastThreadEvent.eventId,
            threadRootId,
          );
        } catch (e) {
          debugPrint('[Kohera] Failed to mark thread as read: $e');
        }
        return;
      }

      if (roomRepository.notificationCount(roomId) == 0) return;
      final visible = messages;
      final lastMainEvent = visible.isNotEmpty ? visible.first : null;
      if (lastMainEvent == null) return;
      try {
        await roomRepository.markRead(
          roomId,
          lastMainEvent.eventId,
          sendPublicReceipt: sendPublicReadReceipts,
        );
      } catch (e) {
        debugPrint('[Kohera] Failed to mark as read: $e');
      }
    });
  }

  // ── Navigation ─────────────────────────────────────────

  Future<void> reloadTimelineAt(String eventId) async {
    _detachTimeline();
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();

    final gen = ++_initGeneration;
    final timeline = await messageRepository.getTimeline(
      roomId,
      eventContextId: eventId,
    );
    if (gen != _initGeneration || _disposed || timeline == null) {
      timeline?.dispose();
      return;
    }
    _attachTimeline(timeline);
  }

  /// Reloads the timeline at the live edge (`eventContextId: null`),
  /// restoring the full sync-subscribed timeline. Used by the
  /// jump-to-latest affordance to escape a fragmented context view.
  Future<void> reloadTimelineAtLive() async {
    _detachTimeline();
    _cachedMessages = null;
    _cachedReceipts = null;
    notifyListeners();

    final gen = ++_initGeneration;
    _initialFullyReadId = roomRepository.fullyReadMarkerId(roomId);
    try {
      await messageRepository.preDecryptRoomHistory(roomId);
    } catch (_) {}
    if (gen != _initGeneration || _disposed) return;
    final timeline = await messageRepository.getTimeline(roomId);
    if (gen != _initGeneration || _disposed || timeline == null) {
      timeline?.dispose();
      return;
    }
    _attachTimeline(timeline);
    _markAsRead();
    messageRepository.requestMissingSessionKeys(roomId);
  }

  // ── Visible events filtering ───────────────────────────

  static List<KoheraTimelineEvent> buildVisibleEvents(
    Iterable<KoheraTimelineEvent> timelineEvents, {
    List<KoheraTimelineEvent>? extraEvents,
    String? threadRootId,
    List<String> ignoredUserIds = const [],
  }) {
    final seen = <String>{};
    final merged = <KoheraTimelineEvent>[];
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
              !ignoredUserIds.contains(e.senderId) &&
              (((e.type == KoheraEventTypes.message ||
                          e.type == KoheraEventTypes.encrypted) &&
                      e.relationshipType != KoheraRelationshipTypes.edit &&
                      !_isCallMemberEvent(e)) ||
                  callEventTypes.contains(e.type) ||
                  _isStateEvent(e) ||
                  e.type == KoheraEventTypes.sticker ||
                  e.type == KoheraEventTypes.pollStart) &&
              _matchesThread(e, threadRootId),
        )
        .toList()
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
  }

  static bool _matchesThread(KoheraTimelineEvent event, String? threadRootId) {
    if (threadRootId == null) {
      return event.relationshipType != KoheraRelationshipTypes.thread;
    }
    if (event.eventId == threadRootId) return true;
    if (event.relationshipType != KoheraRelationshipTypes.thread) return false;
    return event.relationshipEventId == threadRootId;
  }

  static bool _isCallEvent(KoheraTimelineEvent event) =>
      callEventTypes.contains(event.type);

  static bool _isStateEvent(KoheraTimelineEvent event) {
    if (event.type == KoheraEventTypes.roomName ||
        event.type == KoheraEventTypes.roomTopic ||
        event.type == KoheraEventTypes.roomAvatar ||
        event.type == KoheraEventTypes.roomTombstone) {
      return true;
    }
    if (event.type == KoheraEventTypes.roomMember) {
      return !_isNoOpMemberEvent(event);
    }
    return false;
  }

  static bool _isNoOpMemberEvent(KoheraTimelineEvent event) {
    final prev = event.prevContent;
    if (prev == null) return false;
    final curr = event.content;
    final prevMembership = prev['membership'];
    final currMembership = curr['membership'];
    if (prevMembership != currMembership) return false;
    if (prev['displayname'] != curr['displayname']) return false;
    if (prev['avatar_url'] != curr['avatar_url']) return false;
    return true;
  }

  static bool _isCallMemberEvent(KoheraTimelineEvent event) =>
      event.type == kCallMember ||
      event.type == kCallMemberMsc ||
      event.body.contains(kCallMember) ||
      event.body.contains(kCallMemberMsc);

  Duration? _callDuration(KoheraTimelineEvent event) {
    if (event.type != kCallHangup) return null;
    final reason = event.contentString('reason');
    if (reason == kHangupInviteTimeout) return null;

    final hangupCallId = event.contentString('call_id');
    final events = _timeline?.events;
    if (events == null) return null;

    KoheraTimelineEvent? matchedInvite;
    for (final e in events) {
      if (e.type != kCallInvite) continue;
      if (!e.originServerTs.isBefore(event.originServerTs)) continue;
      if (hangupCallId != null &&
          hangupCallId.isNotEmpty &&
          e.contentString('call_id') == hangupCallId) {
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

  // ── ChatMessageData assembly ───────────────────────────

  List<ChatMessageData> _buildMessageData(List<KoheraTimelineEvent> visible) {
    final uid = myUserId ?? '';
    final threadChildren = _threadChildrenByRoot();
    final result = <ChatMessageData>[];

    for (var i = 0; i < visible.length; i++) {
      final event = visible[i];
      final prevSender =
          i + 1 < visible.length ? visible[i + 1].senderId : null;
      final isFirst = event.senderId != prevSender;
      final category = _classifyEvent(event);

      var hasThread = false;
      var replyCount = 0;
      var unreadCount = 0;
      if (event.hasAggregation(KoheraRelationshipTypes.thread)) {
        hasThread = true;
        replyCount = event.aggregationCount(KoheraRelationshipTypes.thread);
        unreadCount = _threadUnreadCount(
          event.eventId,
          uid,
          threadChildren[event.eventId] ?? const [],
        );
      }

      final media = switch (category) {
        MessageCategory.sticker => event.media,
        MessageCategory.message => event.redacted ? null : event.media,
        _ => null,
      };

      result.add(
        ChatMessageData(
          message: event.display ?? _fallbackDisplay(event),
          category: category,
          isMe: event.senderId == uid,
          isFirst: isFirst,
          isPinned: roomRepository.isPinned(roomId, event.eventId),
          canPin: !event.redacted &&
              roomRepository.canChangePinnedEvents(roomId),
          canRedact: event.canRedact,
          hasThread: hasThread,
          threadReplyCount: replyCount,
          threadUnreadCount: unreadCount,
          stateEventText: category == MessageCategory.stateEvent
              ? event.stateEventText
              : null,
          reactions: event.reactions,
          media: media,
          mediaController: media == null
              ? null
              : messageRepository.mediaControllerFor(roomId, event.eventId),
          callDuration: category == MessageCategory.callEvent
              ? _callDuration(event)
              : null,
          poll: category == MessageCategory.poll ? event.poll : null,
        ),
      );
    }
    return result;
  }

  /// Groups thread children of the current timeline by root event ID.
  Map<String, List<KoheraTimelineEvent>> _threadChildrenByRoot() {
    final events = _timeline?.events;
    if (events == null) return const {};
    final map = <String, List<KoheraTimelineEvent>>{};
    for (final e in events) {
      if (e.relationshipType != KoheraRelationshipTypes.thread) continue;
      final rootId = e.relationshipEventId;
      if (rootId == null) continue;
      (map[rootId] ??= []).add(e);
    }
    return map;
  }

  int _threadUnreadCount(
    String rootEventId,
    String uid,
    List<KoheraTimelineEvent> children,
  ) {
    final receiptTs = roomRepository.latestOwnThreadReceiptTs(
      roomId,
      rootEventId,
    );
    var count = 0;
    for (final child in children) {
      if (child.senderId == uid) continue;
      if (child.originServerTs.millisecondsSinceEpoch > receiptTs) count++;
    }
    return count;
  }

  MessageCategory _classifyEvent(KoheraTimelineEvent event) {
    if (_isCallEvent(event)) return MessageCategory.callEvent;
    if (_isStateEvent(event)) return MessageCategory.stateEvent;
    if (event.type == KoheraEventTypes.sticker) return MessageCategory.sticker;
    if (event.type == KoheraEventTypes.pollStart) return MessageCategory.poll;
    return MessageCategory.message;
  }

  /// Minimal display model for events converted without display
  /// resolution. Timeline events normally carry a pre-resolved
  /// [KoheraTimelineEvent.display].
  KoheraMessageDisplay _fallbackDisplay(KoheraTimelineEvent event) {
    return KoheraMessageDisplay(
      eventId: event.eventId,
      senderId: event.senderId,
      senderName: event.senderId,
      body: event.body,
      messageType: event.messageType ?? '',
      eventType: event.type,
      timestamp: event.originServerTs,
      status: KoheraMessageStatus.sent,
      content: event.content,
      isRedacted: event.redacted,
    );
  }

  // ── Dispose ────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _readMarkerTimer?.cancel();
    _detachTimeline();
    super.dispose();
  }
}

import 'package:clock/clock.dart';
import 'package:kohera/core/utils/word_boundary.dart';
import 'package:kohera/data/repositories/push_repository.dart';
import 'package:kohera/data/utils/event_preview.dart';
import 'package:kohera/features/notifications/enum/inbox_filter.dart';
import 'package:kohera/features/notifications/models/kohera_notification_item.dart';
import 'package:kohera/features/notifications/models/notification_group.dart';
import 'package:kohera/features/notifications/models/thread_sub_group.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Event, EventTypes, Membership;

// ── NotificationGrouper ──────────────────────────────────────

class NotificationGrouper {
  NotificationGrouper(this._pushRepo);

  PushRepository _pushRepo;
  set pushRepository(PushRepository value) => _pushRepo = value;

  final Map<String, Event> _decryptedEvents = {};

  // ── Thread-root preview cache ─────────────────────────────
  // Moved here from _SubGroupSectionState so it is scoped to the active
  // client/controller and cleared on account switch instead of being a
  // static map that persists forever.
  final Map<String, String> _rootPreviewCache = {};

  final Map<String, DateTime> _decryptionFailedAt = {};
  static const _negativeCacheTtl = Duration(seconds: 30);

  Map<String, Object?>? decryptedContentFor(String eventId) =>
      _decryptedEvents[eventId]?.content;

  String? rootPreviewFor(String eventId) => _rootPreviewCache[eventId];

  void setRootPreview(String eventId, String preview) =>
      _rootPreviewCache[eventId] = preview;

  void clearCache() {
    _decryptedEvents.clear();
    _rootPreviewCache.clear();
    _decryptionFailedAt.clear();
  }

  // ── Queries ────────────────────────────────────────────────

  String? threadRootIdFor(matrix_sdk.Notification n) {
    final content = _decryptedEvents[n.event.eventId]?.content ?? n.event.content;
    final relatesTo = content['m.relates_to'];
    if (relatesTo is Map &&
        relatesTo['rel_type'] == matrix_sdk.RelationshipTypes.thread) {
      final id = relatesTo['event_id'];
      if (id is String) return id;
    }
    return null;
  }

  bool isMention(matrix_sdk.Notification n) {
    final userId = _pushRepo.userId;
    if (userId == null) return false;
    if (_hasHighlightAction(n.actions)) return true;

    final content = _decryptedEvents[n.event.eventId]?.content ?? n.event.content;
    final mentions = content['m.mentions'];
    if (mentions is Map) {
      final userIds = mentions['user_ids'];
      return (userIds is List && userIds.contains(userId)) ||
          mentions['room'] == true;
    }

    if (n.event.type != EventTypes.Encrypted) return false;
    return _bodyMentions(content, userId, n.roomId);
  }

  bool _bodyMentions(
    Map<String, Object?> content,
    String userId,
    String roomId,
  ) {
    final body = content['body'];
    if (body is! String) return false;

    final lower = body.toLowerCase();
    if (lower.contains(userId.toLowerCase())) return true;

    final displayName = _pushRepo
        .getRoom(roomId)
        ?.unsafeGetUserFromMemoryOrFallback(userId)
        .calcDisplayname();
    return displayName != null &&
        displayName.length >= 2 &&
        containsWord(lower, displayName.toLowerCase());
  }

  // ── Grouping ───────────────────────────────────────────────

  Future<List<NotificationGroup>> group(
    List<matrix_sdk.Notification> notifications,
    InboxFilter filter,
  ) async {
    final candidates = _collectCandidates(notifications);
    await Future.wait(candidates.map(_tryDecrypt));

    final items = <KoheraNotificationItem>[];
    for (final n in candidates) {
      final item = _toItem(n);
      if (filter == InboxFilter.mentions && !item.isMention) continue;
      if (filter == InboxFilter.threads && item.threadRootId == null) continue;
      items.add(item);
    }

    return [
      for (final bucket
          in _bucketByRecency(_collapseCalls(items), (n) => n.roomId))
        NotificationGroup(
          roomId: bucket.key,
          roomName: _pushRepo.getRoom(bucket.key)?.getLocalizedDisplayname() ??
              bucket.key,
          notifications: bucket.value,
          subGroups: _buildSubGroups(bucket.value),
        ),
    ];
  }

  /// Collapses call-membership churn: within each room+thread, keeps only the
  /// most recent call event so one call renders as one row instead of one row
  /// per membership state change.
  List<KoheraNotificationItem> _collapseCalls(
    List<KoheraNotificationItem> items,
  ) {
    final newestCall = <String, int>{};
    for (final item in items) {
      if (!item.isCall) continue;
      final key = '${item.roomId}|${item.threadRootId ?? ''}';
      final ts = newestCall[key];
      if (ts == null || item.timestamp > ts) newestCall[key] = item.timestamp;
    }
    return [
      for (final item in items)
        if (!item.isCall ||
            item.timestamp == newestCall['${item.roomId}|${item.threadRootId ?? ''}'])
          item,
    ];
  }

  List<matrix_sdk.Notification> _collectCandidates(
    List<matrix_sdk.Notification> notifications,
  ) {
    final candidates = <matrix_sdk.Notification>[];
    final seen = <String>{};
    for (final n in notifications) {
      if (n.read || !seen.add(n.event.eventId)) continue;
      final room = _pushRepo.getRoom(n.roomId);
      if (room == null || room.membership != Membership.join) continue;
      candidates.add(n);
    }
    return candidates;
  }

  KoheraNotificationItem _toItem(matrix_sdk.Notification n) {
    final room = _pushRepo.getRoom(n.roomId);
    final event = _decryptedEvents[n.event.eventId] ??
        (room != null ? Event.fromMatrixEvent(n.event, room) : null);
    return KoheraNotificationItem(
      eventId: n.event.eventId,
      roomId: n.roomId,
      senderName: _senderName(n),
      body: event != null && room != null
          ? eventPreviewText(event, room: room, myUserId: _pushRepo.userId)
          : '',
      timestamp: n.ts,
      isRead: n.read,
      isMention: isMention(n),
      isCall: event != null && isCallEvent(event),
      threadRootId: threadRootIdFor(n),
    );
  }

  String _senderName(matrix_sdk.Notification n) {
    final room = _pushRepo.getRoom(n.roomId);
    return room?.unsafeGetUserFromMemoryOrFallback(n.event.senderId)
            .calcDisplayname() ??
        n.event.senderId;
  }

  List<ThreadSubGroup> _buildSubGroups(List<KoheraNotificationItem> items) {
    const mainKey = '__main__';
    return [
      for (final bucket
          in _bucketByRecency(items, (n) => n.threadRootId ?? mainKey))
        ThreadSubGroup(
          threadRootId: bucket.key == mainKey ? null : bucket.key,
          notifications: bucket.value,
        ),
    ];
  }

  List<MapEntry<String, List<KoheraNotificationItem>>> _bucketByRecency(
    List<KoheraNotificationItem> items,
    String Function(KoheraNotificationItem) keyOf,
  ) {
    final buckets = <String, List<KoheraNotificationItem>>{};
    final order = <String>[];
    for (final n in items) {
      final key = keyOf(n);
      buckets.putIfAbsent(key, () {
        order.add(key);
        return [];
      }).add(n);
    }
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    order.sort((a, b) {
      final cmp = _mostRecentTimestamp(buckets[b]!).compareTo(_mostRecentTimestamp(buckets[a]!));
      return cmp != 0 ? cmp : rank[a]!.compareTo(rank[b]!);
    });
    return [for (final key in order) MapEntry(key, buckets[key]!)];
  }

  Future<void> _tryDecrypt(matrix_sdk.Notification n) async {
    if (n.event.type != EventTypes.Encrypted) return;
    final eventId = n.event.eventId;
    if (_decryptedEvents.containsKey(eventId)) return;
    if (_isFailureCached(eventId)) return;
    final room = _pushRepo.getRoom(n.roomId);
    if (room == null) return;
    try {
      final event = Event.fromMatrixEvent(n.event, room);
      final decrypted = await _pushRepo.decryptRoomEvent(room, event)
          .timeout(const Duration(seconds: 3));
      if (decrypted != null) {
        _decryptedEvents[eventId] = decrypted;
        _decryptionFailedAt.remove(eventId);
        return;
      }
    } catch (_) {}
    _decryptionFailedAt[eventId] = clock.now();
  }

  bool _isFailureCached(String eventId) {
    final failedAt = _decryptionFailedAt[eventId];
    if (failedAt == null) return false;
    if (clock.now().difference(failedAt) > _negativeCacheTtl) {
      _decryptionFailedAt.remove(eventId);
      return false;
    }
    return true;
  }
}

// ── Helpers ──────────────────────────────────────────────────

bool _hasHighlightAction(List<Object?> actions) {
  for (final action in actions) {
    if (action is Map && action['set_tweak'] == 'highlight') {
      final value = action['value'];
      if (value == null || value == true) return true;
    }
  }
  return false;
}

int _mostRecentTimestamp(Iterable<KoheraNotificationItem> items) =>
    items.map((n) => n.timestamp).reduce((a, b) => a > b ? a : b);

import 'package:kohera/core/utils/word_boundary.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client, Event, EventTypes, Membership;

// ── Filter enum ──────────────────────────────────────────────

enum InboxFilter { all, mentions, threads, invitations }

// ── Grouped notification model ───────────────────────────────

class ThreadSubGroup {
  final String? threadRootId;
  final List<matrix_sdk.Notification> notifications;

  const ThreadSubGroup({
    required this.threadRootId,
    required this.notifications,
  });
}

class NotificationGroup {
  final String roomId;
  final String roomName;
  final List<matrix_sdk.Notification> notifications;
  final List<ThreadSubGroup> subGroups;

  const NotificationGroup({
    required this.roomId,
    required this.roomName,
    required this.notifications,
    required this.subGroups,
  });
}

// ── NotificationGrouper ──────────────────────────────────────

class NotificationGrouper {
  NotificationGrouper(this._client);

  Client _client;
  set client(Client value) => _client = value;

  final Map<String, Map<String, Object?>> _decryptedContent = {};

  Map<String, Object?>? decryptedContentFor(String eventId) =>
      _decryptedContent[eventId];

  void clearCache() => _decryptedContent.clear();

  // ── Queries ────────────────────────────────────────────────

  String? threadRootIdFor(matrix_sdk.Notification n) {
    final content = _decryptedContent[n.event.eventId] ?? n.event.content;
    final relatesTo = content['m.relates_to'];
    if (relatesTo is Map &&
        relatesTo['rel_type'] == matrix_sdk.RelationshipTypes.thread) {
      final id = relatesTo['event_id'];
      if (id is String) return id;
    }
    return null;
  }

  bool isMention(matrix_sdk.Notification n) {
    final userId = _client.userID;
    if (userId == null) return false;
    if (_hasHighlightAction(n.actions)) return true;

    final content = _decryptedContent[n.event.eventId] ?? n.event.content;
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

    final displayName = _client
        .getRoomById(roomId)
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
    final visible = await _filterVisible(notifications, filter);
    return [
      for (final bucket in _bucketByRecency(visible, (n) => n.roomId))
        NotificationGroup(
          roomId: bucket.key,
          roomName: _client.getRoomById(bucket.key)?.getLocalizedDisplayname() ??
              bucket.key,
          notifications: bucket.value,
          subGroups: _buildSubGroups(bucket.value),
        ),
    ];
  }

  Future<List<matrix_sdk.Notification>> _filterVisible(
    List<matrix_sdk.Notification> notifications,
    InboxFilter filter,
  ) async {
    final visible = <matrix_sdk.Notification>[];
    final seen = <String>{};
    for (final n in notifications) {
      if (n.read || !seen.add(n.event.eventId)) continue;
      final room = _client.getRoomById(n.roomId);
      if (room == null || room.membership != Membership.join) continue;
      await _tryDecrypt(n);
      if (filter == InboxFilter.mentions && !isMention(n)) continue;
      if (filter == InboxFilter.threads && threadRootIdFor(n) == null) continue;
      visible.add(n);
    }
    return visible;
  }

  List<ThreadSubGroup> _buildSubGroups(
    List<matrix_sdk.Notification> notifications,
  ) {
    const mainKey = '__main__';
    return [
      for (final bucket
          in _bucketByRecency(notifications, (n) => threadRootIdFor(n) ?? mainKey))
        ThreadSubGroup(
          threadRootId: bucket.key == mainKey ? null : bucket.key,
          notifications: bucket.value,
        ),
    ];
  }

  List<MapEntry<String, List<matrix_sdk.Notification>>> _bucketByRecency(
    List<matrix_sdk.Notification> notifications,
    String Function(matrix_sdk.Notification) keyOf,
  ) {
    final buckets = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];
    for (final n in notifications) {
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

  Future<Map<String, Object?>?> _tryDecrypt(matrix_sdk.Notification n) async {
    if (n.event.type != EventTypes.Encrypted) return null;
    final cached = _decryptedContent[n.event.eventId];
    if (cached != null) return cached;
    final room = _client.getRoomById(n.roomId);
    if (room == null) return null;
    try {
      final event = Event.fromMatrixEvent(n.event, room);
      final decrypted = await room.client.encryption
          ?.decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      if (decrypted != null) {
        _decryptedContent[n.event.eventId] = decrypted.content;
        return decrypted.content;
      }
    } catch (_) {}
    return null;
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

int _mostRecentTimestamp(Iterable<matrix_sdk.Notification> notifications) =>
    notifications.map((n) => n.ts).reduce((a, b) => a > b ? a : b);

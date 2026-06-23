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

/// Turns a flat notification list into room/thread groups, applying the
/// active [InboxFilter] and caching decrypted content. Owns no controller
/// state — given a [Client] and a list, it produces grouped output.
class NotificationGrouper {
  NotificationGrouper(this._client);

  Client _client;
  set client(Client value) => _client = value;

  final Map<String, Map<String, Object?>> _decryptedContent = {};

  Map<String, Object?>? decryptedContentFor(String eventId) =>
      _decryptedContent[eventId];

  void clearCache() => _decryptedContent.clear();

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
      if (userIds is List && userIds.contains(userId)) return true;
      return mentions['room'] == true;
    }

    if (n.event.type != EventTypes.Encrypted) return false;

    final body = content['body'];
    if (body is! String) return false;

    final lower = body.toLowerCase();
    if (lower.contains(userId.toLowerCase())) return true;

    final displayName = _client
        .getRoomById(n.roomId)
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
    final map = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];
    final seen = <String>{};

    for (final n in notifications) {
      if (n.read) continue;
      if (!seen.add(n.event.eventId)) continue;
      final room = _client.getRoomById(n.roomId);
      if (room == null || room.membership != Membership.join) continue;
      await _tryDecrypt(n);
      if (filter == InboxFilter.mentions && !isMention(n)) continue;
      if (filter == InboxFilter.threads && threadRootIdFor(n) == null) {
        continue;
      }
      map.putIfAbsent(n.roomId, () {
        order.add(n.roomId);
        return [];
      });
      map[n.roomId]!.add(n);
    }

    final insertionIndex = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    order.sort((a, b) {
      final cmp = _maxTs(map[b]!).compareTo(_maxTs(map[a]!));
      if (cmp != 0) return cmp;
      return insertionIndex[a]!.compareTo(insertionIndex[b]!);
    });

    return order.map((roomId) {
      final room = _client.getRoomById(roomId);
      final notifications = map[roomId]!;
      return NotificationGroup(
        roomId: roomId,
        roomName: room?.getLocalizedDisplayname() ?? roomId,
        notifications: notifications,
        subGroups: _buildSubGroups(notifications),
      );
    }).toList();
  }

  List<ThreadSubGroup> _buildSubGroups(
    List<matrix_sdk.Notification> notifications,
  ) {
    const mainKey = '__main__';
    final buckets = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];
    for (final n in notifications) {
      final key = threadRootIdFor(n) ?? mainKey;
      if (!buckets.containsKey(key)) order.add(key);
      buckets.putIfAbsent(key, () => []).add(n);
    }
    order.sort((a, b) => _maxTs(buckets[b]!).compareTo(_maxTs(buckets[a]!)));
    return [
      for (final key in order)
        ThreadSubGroup(
          threadRootId: key == mainKey ? null : key,
          notifications: buckets[key]!,
        ),
    ];
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

int _maxTs(Iterable<matrix_sdk.Notification> notifications) =>
    notifications.map((n) => n.ts).reduce((a, b) => a > b ? a : b);

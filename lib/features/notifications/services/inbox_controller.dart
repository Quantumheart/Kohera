import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/notification_filter.dart';
import 'package:kohera/core/utils/word_boundary.dart';
import 'package:kohera/features/notifications/services/apns_push_service.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart'
    show Client, Event, EventTypes, MatrixException, Membership;

// ── Push-action helper ───────────────────────────────────────

bool _hasHighlightAction(List<Object?> actions) {
  for (final action in actions) {
    if (action is Map && action['set_tweak'] == 'highlight') {
      final value = action['value'];
      if (value == null || value == true) return true;
    }
  }
  return false;
}

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

// ── InboxController ──────────────────────────────────────────
class InboxController extends ChangeNotifier {
  InboxController({required Client client}) : _client = client;

  Client _client;
  Client get client => _client;
  bool _disposed = false;

  List<NotificationGroup> _grouped = [];
  List<NotificationGroup> get grouped => List.unmodifiable(_grouped);
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String? _error;
  String? get error => _error;
  String? _nextToken;
  InboxFilter _filter = InboxFilter.all;
  InboxFilter get filter => _filter;

  StreamSubscription<matrix_sdk.SyncUpdate>? _syncSub;
  Timer? _debounce;
  int _pollingRefCount = 0;
  bool _markingAsRead = false;
  bool _tokenExpired = false;
  static const _debounceDelay = Duration(milliseconds: 750);

  int _fetchGeneration = 0;
  int _cachedUnreadCount = 0;

  final Map<String, Map<String, Object?>> _decryptedContent = {};

  // ── Public getters ─────────────────────────────────────────

  int get unreadCount => _cachedUnreadCount;

  bool get hasMore => _nextToken != null;

  Map<String, Object?>? decryptedContentFor(String eventId) =>
      _decryptedContent[eventId];

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

  // ── Unread count cache helper ──────────────────────────────

  void _updateUnreadCount() {
    var count = 0;
    for (final group in _grouped) {
      count += group.notifications.where((n) => !n.read).length;
    }
    _cachedUnreadCount = count;
  }

  // ── Fetch ──────────────────────────────────────────────────

  Future<void> fetch() async {
    final gen = ++_fetchGeneration;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final response = await _client.getNotifications(limit: 30);
      if (_disposed || gen != _fetchGeneration) return;
      _nextToken = response.nextToken;
      _grouped = await _groupByRoom(response.notifications);
      _updateUnreadCount();
    } catch (e) {
      if (_disposed || gen != _fetchGeneration) return;
      if (_isTokenExpired(e)) {
        _tokenExpired = true;
        _isLoading = false;
        _unbindSync();
        return;
      }
      _error = e.toString();
      debugPrint('[Kohera] Inbox fetch error: $e');
    } finally {
      if (!_disposed && gen == _fetchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_nextToken == null || _isLoading) return;

    final gen = ++_fetchGeneration;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final response = await _client.getNotifications(
        limit: 30,
        from: _nextToken,
      );
      if (_disposed || gen != _fetchGeneration) return;
      _nextToken = response.nextToken;

      // Merge new notifications into existing groups
      final all = <matrix_sdk.Notification>[];
      for (final group in _grouped) {
        all.addAll(group.notifications);
      }
      all.addAll(response.notifications);
      _grouped = await _groupByRoom(all);
      _updateUnreadCount();
    } catch (e) {
      if (_disposed || gen != _fetchGeneration) return;
      _error = e.toString();
      debugPrint('[Kohera] Inbox loadMore error: $e');
    } finally {
      if (!_disposed && gen == _fetchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ── Filter ─────────────────────────────────────────────────

  int get invitationCount =>
      _client.rooms.where((r) => r.membership == Membership.invite).length;

  void setFilter(InboxFilter newFilter) {
    if (_filter == newFilter) return;
    _filter = newFilter;
    if (newFilter == InboxFilter.invitations) {
      if (!_disposed) notifyListeners();
      return;
    }
    _grouped = [];
    _nextToken = null;
    _updateUnreadCount();
    if (!_disposed) notifyListeners();
    unawaited(fetch().catchError((Object e) => debugPrint('[Kohera] Inbox fetch error: $e')));
  }

  // ── Sync-driven invalidation ───────────────────────────────

  void startPolling() {
    _pollingRefCount++;
    if (_pollingRefCount == 1) {
      _bindSync();
    }
  }

  void stopPolling() {
    _pollingRefCount = (_pollingRefCount - 1).clamp(0, 999);
    if (_pollingRefCount == 0) {
      _unbindSync();
    }
  }

  void _bindSync() {
    final existing = _syncSub;
    if (existing != null) unawaited(existing.cancel());
    _syncSub = _client.onSync.stream.listen(_onSync);
  }

  void _unbindSync() {
    unawaited(_syncSub?.cancel() ?? Future.value());
    _syncSub = null;
    _debounce?.cancel();
    _debounce = null;
  }

  void _onSync(matrix_sdk.SyncUpdate update) {
    if (_disposed || _tokenExpired) return;
    if (!_shouldInvalidate(update)) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (_disposed || _tokenExpired) return;
      if (_isLoading || _markingAsRead) return;
      unawaited(fetch());
    });
  }

  bool _shouldInvalidate(matrix_sdk.SyncUpdate update) {
    final rooms = update.rooms;
    if (rooms == null) return false;
    final joins = rooms.join;
    if (joins != null) {
      for (final entry in joins.values) {
        final timelineEvents = entry.timeline?.events;
        if (timelineEvents != null && timelineEvents.isNotEmpty) return true;
        final ephemeral = entry.ephemeral;
        if (ephemeral != null) {
          for (final ev in ephemeral) {
            if (ev.type == 'm.receipt') return true;
          }
        }
      }
    }
    if (rooms.invite != null && rooms.invite!.isNotEmpty) return true;
    if (rooms.leave != null && rooms.leave!.isNotEmpty) return true;
    return false;
  }

  // ── Mark as read ───────────────────────────────────────────

  Future<void> markRoomAsRead(String roomId) async {
    if (_tokenExpired) return;
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    String? mainEventId;
    var mainTs = -1;
    final perThread = <String, ({String eventId, int ts})>{};
    for (final group in _grouped) {
      if (group.roomId != roomId) continue;
      for (final n in group.notifications) {
        final threadId = threadRootIdFor(n);
        if (threadId != null) {
          final cur = perThread[threadId];
          if (cur == null || n.ts > cur.ts) {
            perThread[threadId] = (eventId: n.event.eventId, ts: n.ts);
          }
        } else if (n.ts > mainTs) {
          mainTs = n.ts;
          mainEventId = n.event.eventId;
        }
      }
      break;
    }
    mainEventId ??= room.lastEvent?.eventId;
    if (mainEventId == null && perThread.isEmpty) return;

    _markingAsRead = true;
    _grouped = [
      for (final g in _grouped)
        if (g.roomId != roomId) g,
    ];
    _updateUnreadCount();
    final remainingUnread = totalUnreadCount(_client) - room.notificationCount;
    final remainingBadge = remainingUnread < 0 ? 0 : remainingUnread;
    unawaited(ApnsPushService.setBadge(remainingBadge));
    if (!_disposed) notifyListeners();

    final maxThreadTs = perThread.values.fold<int>(
      -1,
      (acc, e) => e.ts > acc ? e.ts : acc,
    );
    final shouldPostMain = mainEventId != null && mainTs >= maxThreadTs;

    try {
      await Future.wait([
        if (shouldPostMain)
          room.setReadMarker(mainEventId, mRead: mainEventId),
        for (final entry in perThread.entries)
          _client.postReceipt(
            roomId,
            matrix_sdk.ReceiptType.mRead,
            entry.value.eventId,
            threadId: entry.key,
          ),
      ]);
    } catch (e) {
      if (_isTokenExpired(e)) {
        _tokenExpired = true;
        _unbindSync();
        _markingAsRead = false;
        return;
      }
      debugPrint('[Kohera] Inbox markRoomAsRead error: $e');
      await fetch();
    } finally {
      _markingAsRead = false;
    }
  }

  // ── Account switching ──────────────────────────────────────

  void updateClient(Client newClient) {
    _tokenExpired = false;
    if (identical(_client, newClient)) return;
    final wasActive = _pollingRefCount > 0;
    _unbindSync();
    _client = newClient;
    _grouped = [];
    _decryptedContent.clear();
    _nextToken = null;
    _isLoading = false;
    _error = null;
    _updateUnreadCount();
    if (wasActive) _bindSync();
    if (!_disposed) notifyListeners();
    unawaited(fetch().catchError((Object e) => debugPrint('[Kohera] Inbox fetch error: $e')));
  }

  // ── Token expiry guard ─────────────────────────────────────

  static bool _isTokenExpired(Object e) =>
      e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN';

  // ── Mention detection ──────────────────────────────────────

  bool isMention(matrix_sdk.Notification n) {
    final userId = _client.userID;
    if (userId == null) return false;

    if (_hasHighlightAction(n.actions)) return true;

    final content =
        _decryptedContent[n.event.eventId] ?? n.event.content;

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

  // ── Helpers ────────────────────────────────────────────────

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

  Future<List<NotificationGroup>> _groupByRoom(
      List<matrix_sdk.Notification> notifications,) async {
    final map = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];

    for (final n in notifications) {
      if (n.read) continue;
      final room = _client.getRoomById(n.roomId);
      if (room == null || room.membership != Membership.join) continue;
      await _tryDecrypt(n);
      if (_filter == InboxFilter.mentions && !isMention(n)) continue;
      if (_filter == InboxFilter.threads && threadRootIdFor(n) == null) {
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
    int maxTs(String roomId) =>
        map[roomId]!.map((n) => n.ts).reduce((a, b) => a > b ? a : b);
    order.sort((a, b) {
      final cmp = maxTs(b).compareTo(maxTs(a));
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
    int maxTs(String k) =>
        buckets[k]!.map((n) => n.ts).reduce((a, b) => a > b ? a : b);
    order.sort((a, b) => maxTs(b).compareTo(maxTs(a)));
    return [
      for (final key in order)
        ThreadSubGroup(
          threadRootId: key == mainKey ? null : key,
          notifications: buckets[key]!,
        ),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _unbindSync();
    super.dispose();
  }
}

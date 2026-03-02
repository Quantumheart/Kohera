import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client;

// ── Filter enum ──────────────────────────────────────────────
enum InboxFilter { all, mentions }

// ── Grouped notification model ───────────────────────────────
class NotificationGroup {
  final String roomId;
  final String roomName;
  final List<matrix_sdk.Notification> notifications;

  const NotificationGroup({
    required this.roomId,
    required this.roomName,
    required this.notifications,
  });
}

// ── InboxController ──────────────────────────────────────────
class InboxController extends ChangeNotifier {
  InboxController({required Client client}) : _client = client;

  Client _client;
  Client get client => _client;

  List<NotificationGroup> grouped = [];
  bool isLoading = false;
  String? error;
  String? _nextToken;
  InboxFilter filter = InboxFilter.all;

  Timer? _pollTimer;

  // ── Public getters ─────────────────────────────────────────

  int get unreadCount {
    var count = 0;
    for (final group in grouped) {
      count +=
          group.notifications.where((n) => !n.read).length;
    }
    return count;
  }

  bool get hasMore => _nextToken != null;

  // ── Fetch ──────────────────────────────────────────────────

  Future<void> fetch() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final response = await _client.getNotifications(
        limit: 30,
        only: filter == InboxFilter.mentions ? 'highlight' : null,
      );
      _nextToken = response.nextToken;
      grouped = _groupByRoom(response.notifications);
    } catch (e) {
      error = e.toString();
      debugPrint('[Lattice] Inbox fetch error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_nextToken == null || isLoading) return;

    isLoading = true;
    notifyListeners();

    try {
      final response = await _client.getNotifications(
        limit: 30,
        from: _nextToken,
        only: filter == InboxFilter.mentions ? 'highlight' : null,
      );
      _nextToken = response.nextToken;

      // Merge new notifications into existing groups
      final all = <matrix_sdk.Notification>[];
      for (final group in grouped) {
        all.addAll(group.notifications);
      }
      all.addAll(response.notifications);
      grouped = _groupByRoom(all);
    } catch (e) {
      error = e.toString();
      debugPrint('[Lattice] Inbox loadMore error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Filter ─────────────────────────────────────────────────

  void setFilter(InboxFilter newFilter) {
    if (filter == newFilter) return;
    filter = newFilter;
    grouped = [];
    _nextToken = null;
    notifyListeners();
    fetch();
  }

  // ── Polling ────────────────────────────────────────────────

  void startPolling() {
    stopPolling();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => _pollOnce(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    try {
      final response = await _client.getNotifications(
        limit: 30,
        only: filter == InboxFilter.mentions ? 'highlight' : null,
      );
      _nextToken = response.nextToken;
      grouped = _groupByRoom(response.notifications);
      notifyListeners();
    } catch (e) {
      debugPrint('[Lattice] Inbox poll error: $e');
    }
  }

  // ── Mark as read ───────────────────────────────────────────

  Future<void> markRoomAsRead(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    final lastEvent = room.lastEvent;
    if (lastEvent == null) return;

    try {
      await room.setReadMarker(lastEvent.eventId);
      // Re-fetch to update state
      await fetch();
    } catch (e) {
      debugPrint('[Lattice] Inbox markRoomAsRead error: $e');
    }
  }

  // ── Account switching ──────────────────────────────────────

  void updateClient(Client newClient) {
    _client = newClient;
    grouped = [];
    _nextToken = null;
    error = null;
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────

  List<NotificationGroup> _groupByRoom(
      List<matrix_sdk.Notification> notifications) {
    final map = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];

    for (final n in notifications) {
      map.putIfAbsent(n.roomId, () {
        order.add(n.roomId);
        return [];
      });
      map[n.roomId]!.add(n);
    }

    return order.map((roomId) {
      final room = _client.getRoomById(roomId);
      return NotificationGroup(
        roomId: roomId,
        roomName: room?.getLocalizedDisplayname() ?? roomId,
        notifications: map[roomId]!,
      );
    }).toList();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

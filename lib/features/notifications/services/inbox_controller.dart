import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/notification_filter.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/notifications/enum/inbox_filter.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/models/notification_group.dart';
import 'package:kohera/features/notifications/services/apns_push_service.dart';
import 'package:kohera/features/notifications/services/notification_grouper.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client, MatrixException, Membership;

export 'package:kohera/features/notifications/services/notification_grouper.dart';

// ── InboxController ──────────────────────────────────────────
class InboxController extends ChangeNotifier {
  InboxController({required Client client})
      : _client = client,
        _grouper = NotificationGrouper(client);

  Client _client;
  Client get client => _client;
  final NotificationGrouper _grouper;
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
  List<matrix_sdk.Notification> _rawNotifications = [];

  // ── Public getters ─────────────────────────────────────────

  int get unreadCount => totalUnreadCount(_client);

  bool get hasMore => _nextToken != null;

  // ── Thread-root preview cache (cleared on account switch) ─────
  String? rootPreviewFor(String eventId) => _grouper.rootPreviewFor(eventId);
  void setRootPreview(String eventId, String preview) =>
      _grouper.setRootPreview(eventId, preview);

  Future<String?> loadRootPreview(String roomId, String eventId) async {
    final cached = _grouper.rootPreviewFor(eventId);
    if (cached != null) return cached;
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    try {
      final event = await room.getEventById(eventId);
      if (event == null) return null;
      final body = stripReplyFallback(event.body).trim();
      if (body.isEmpty) return null;
      final truncated =
          body.length > 80 ? '${body.substring(0, 80)}…' : body;
      final preview = InboxText.inReplyTo(truncated);
      _grouper.setRootPreview(eventId, preview);
      return preview;
    } catch (_) {
      return null;
    }
  }

  // ── Fetch ──────────────────────────────────────────────────


  Future<void> fetch() => _withLoad((gen) async {
        final response = await _client.getNotifications(limit: 30);
        if (_disposed || gen != _fetchGeneration) return null;
        _rawNotifications = response.notifications;
        final grouped = await _grouper.group(response.notifications, _filter);
        return (grouped: grouped, token: response.nextToken);
      });

  Future<void> refresh() => _withLoad((gen) async {
        final response = await _client.getNotifications(limit: 30);
        if (_disposed || gen != _fetchGeneration) return null;
        final headIds =
            response.notifications.map((n) => n.event.eventId).toSet();
        final merged = [
          ...response.notifications,
          for (final n in _rawNotifications)
            if (!headIds.contains(n.event.eventId)) n,
        ];
        _rawNotifications = merged;
        final grouped = await _grouper.group(merged, _filter);
        return (grouped: grouped, token: _nextToken);
      });

  Future<void> loadMore() async {
    if (_nextToken == null || _isLoading) return;
    await _withLoad((gen) async {
      final response = await _client.getNotifications(
        limit: 30,
        from: _nextToken,
      );
      if (_disposed || gen != _fetchGeneration) return null;
      final merged = [..._rawNotifications, ...response.notifications];
      _rawNotifications = merged;
      final grouped = await _grouper.group(merged, _filter);
      return (grouped: grouped, token: response.nextToken);
    });
  }

  Future<void> _withLoad(
    Future<({List<NotificationGroup> grouped, String? token})?> Function(int gen)
        build,
  ) async {
    final gen = ++_fetchGeneration;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final result = await build(gen);
      if (result == null || _disposed || gen != _fetchGeneration) return;
      _nextToken = result.token;
      _grouped = result.grouped;
    } catch (e) {
      if (_disposed || gen != _fetchGeneration) return;
      if (_isTokenExpired(e)) {
        _tokenExpired = true;
        _isLoading = false;
        _unbindSync();
        return;
      }
      _error = e.toString();
      debugPrint('[Kohera] Inbox load error: $e');
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
    _resetList();
    if (!_disposed) notifyListeners();
    _startFetch();
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
      unawaited(refresh());
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
        final threadId = n.threadRootId;
        if (threadId != null) {
          final cur = perThread[threadId];
          if (cur == null || n.timestamp > cur.ts) {
            perThread[threadId] = (eventId: n.eventId, ts: n.timestamp);
          }
        } else if (n.timestamp > mainTs) {
          mainTs = n.timestamp;
          mainEventId = n.eventId;
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
    _rawNotifications = [
      for (final n in _rawNotifications)
        if (n.roomId != roomId) n,
    ];
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
      await refresh();
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
    _grouper
      ..client = newClient
      ..clearCache();
    _resetList();
    _isLoading = false;
    _error = null;
    if (wasActive) _bindSync();
    if (!_disposed) notifyListeners();
    _startFetch();
  }

  // ── State helpers ──────────────────────────────────────────

  void _resetList() {
    _grouped = [];
    _nextToken = null;
    _rawNotifications = [];
  }

  void _startFetch() => unawaited(
        fetch().catchError(
          (Object e) => debugPrint('[Kohera] Inbox fetch error: $e'),
        ),
      );

  static bool _isTokenExpired(Object e) =>
      e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN';

  @override
  void dispose() {
    _disposed = true;
    _unbindSync();
    super.dispose();
  }
}

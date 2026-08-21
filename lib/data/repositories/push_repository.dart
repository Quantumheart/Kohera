import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/media_auth.dart' as media_auth;
import 'package:kohera/core/utils/notification_filter.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

/// Data-layer boundary for push notifications: pusher registration with the
/// homeserver and the room/event/decryption access the platform push handlers
/// need to render incoming notifications.
class PushRepository extends ChangeNotifier {
  PushRepository({required MatrixClientService clientService})
      : _clientService = clientService;

  final MatrixClientService _clientService;
  bool _disposed = false;

  Client get _client => _clientService.client;

  // ── Identity ──────────────────────────────────────────────────

  String? get userId => _client.userID;
  String? get deviceId => _client.deviceID;
  String? get deviceName => _client.deviceName;

  Stream<SyncUpdate> get onSync => _client.onSync.stream;

  // ── Pusher registration ───────────────────────────────────────

  /// Registers [pusher] with the homeserver so it forwards pushes to the
  /// configured gateway.
  Future<void> postPusher(Pusher pusher, {bool append = false}) =>
      _client.postPusher(pusher, append: append);

  /// Removes a previously registered pusher.
  Future<void> deletePusher(PusherId id) => _client.deletePusher(id);

  // ── Push payload access ───────────────────────────────────────

  /// The SDK [Room] for [roomId], or null. Escape hatch for the platform push
  /// handlers that render notifications from raw room/event data.
  Room? getRoom(String roomId) => _client.getRoomById(roomId);

  /// Fetches a single event from the homeserver by [roomId]/[eventId].
  Future<MatrixEvent> getRoomEvent(String roomId, String eventId) =>
      _client.getOneRoomEvent(roomId, eventId);

  /// Decrypts [event] in [room], or null if decryption is unavailable.
  Future<Event?> decryptRoomEvent(Room room, Event event) async =>
      _client.encryption?.decryptRoomEvent(event);

  /// The total unread notification count across all rooms.
  int unreadNotificationCount() => totalUnreadCount(_client);

  // ── Sync ─────────────────────────────────────────────────────

  /// Performs a one-shot sync (used by platform push handlers to catch up
  /// after receiving a push).
  Future<void> oneShotSync() => _client.oneShotSync();

  // ── Notifications API ────────────────────────────────────────

  /// Fetches a page of notifications from the homeserver.
  Future<GetNotificationsResponse> getNotifications({
    int limit = 30,
    String? from,
  }) =>
      _client.getNotifications(limit: limit, from: from);

  /// Posts a read receipt for [eventId] in [roomId].
  Future<void> postReceipt(
    String roomId,
    ReceiptType type,
    String eventId, {
    String? threadId,
  }) =>
      _client.postReceipt(roomId, type, eventId, threadId: threadId);

  /// All rooms the client knows about (used for invite counting).
  Iterable<Room> get rooms => _client.rooms;

  // ── Media helpers (notification avatar rendering) ────────────

  /// Auth headers for a media URL (scoped to the homeserver host).
  Map<String, String>? mediaAuthHeaders(String url) =>
      media_auth.mediaAuthHeaders(_client, url);

  /// Resolves a thumbnail URI for an avatar [mxcUrl].
  Future<Uri> thumbnailUri(
    Uri avatarUrl, {
    int width = 128,
    int height = 128,
  }) =>
      avatarUrl.getThumbnailUri(_client, width: width, height: height);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

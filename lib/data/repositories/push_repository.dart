import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/media_auth.dart' as media_auth;
import 'package:kohera/core/utils/notification_filter.dart';
import 'package:matrix/matrix.dart';

/// Data-layer boundary for push notifications: pusher registration with the
/// homeserver and the room/event/decryption access the platform push handlers
/// need to render incoming notifications.
class PushRepository extends ChangeNotifier {
  PushRepository({required MatrixService matrix}) : _matrix = matrix {
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  // ── Identity ──────────────────────────────────────────────────

  String? get userId => _matrix.client.userID;
  String? get deviceId => _matrix.client.deviceID;
  String? get deviceName => _matrix.client.deviceName;

  Stream<SyncUpdate> get onSync => _matrix.client.onSync.stream;

  // ── Pusher registration ───────────────────────────────────────

  /// Registers [pusher] with the homeserver so it forwards pushes to the
  /// configured gateway.
  Future<void> postPusher(Pusher pusher, {bool append = false}) =>
      _matrix.client.postPusher(pusher, append: append);

  /// Removes a previously registered pusher.
  Future<void> deletePusher(PusherId id) => _matrix.client.deletePusher(id);

  // ── Push payload access ───────────────────────────────────────

  /// The SDK [Room] for [roomId], or null. Escape hatch for the platform push
  /// handlers that render notifications from raw room/event data.
  Room? getRoom(String roomId) => _matrix.client.getRoomById(roomId);

  /// Fetches a single event from the homeserver by [roomId]/[eventId].
  Future<MatrixEvent> getRoomEvent(String roomId, String eventId) =>
      _matrix.client.getOneRoomEvent(roomId, eventId);

  /// Decrypts [event] in [room], or null if decryption is unavailable.
  Future<Event?> decryptRoomEvent(Room room, Event event) async =>
      _matrix.client.encryption?.decryptRoomEvent(event);

  /// The total unread notification count across all rooms.
  int unreadNotificationCount() => totalUnreadCount(_matrix.client);

  // ── Sync ─────────────────────────────────────────────────────

  /// Performs a one-shot sync (used by platform push handlers to catch up
  /// after receiving a push).
  Future<void> oneShotSync() => _matrix.client.oneShotSync();

  // ── Notifications API ────────────────────────────────────────

  /// Fetches a page of notifications from the homeserver.
  Future<GetNotificationsResponse> getNotifications({
    int limit = 30,
    String? from,
  }) =>
      _matrix.client.getNotifications(limit: limit, from: from);

  /// Posts a read receipt for [eventId] in [roomId].
  Future<void> postReceipt(
    String roomId,
    ReceiptType type,
    String eventId, {
    String? threadId,
  }) =>
      _matrix.client.postReceipt(roomId, type, eventId, threadId: threadId);

  /// All rooms the client knows about (used for invite counting).
  Iterable<Room> get rooms => _matrix.client.rooms;

  // ── Media helpers (notification avatar rendering) ────────────

  /// Auth headers for a media URL (scoped to the homeserver host).
  Map<String, String>? mediaAuthHeaders(String url) =>
      media_auth.mediaAuthHeaders(_matrix.client, url);

  /// Resolves a thumbnail URI for an avatar [mxcUrl].
  Future<Uri> thumbnailUri(
    Uri avatarUrl, {
    int width = 128,
    int height = 128,
  }) =>
      avatarUrl.getThumbnailUri(_matrix.client, width: width, height: height);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}

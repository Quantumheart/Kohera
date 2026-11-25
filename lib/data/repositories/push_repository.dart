import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/media_auth.dart' as media_auth;
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

  /// Registers an HTTP pusher with the homeserver, appending to any
  /// existing pushers.
  Future<void> registerHttpPusher({
    required String appId,
    required String pushkey,
    required String appDisplayName,
    required String deviceDisplayName,
    required String lang,
    required Uri gatewayUrl,
    String? profileTag,
    String? format,
  }) =>
      _client.postPusher(
        Pusher(
          appId: appId,
          pushkey: pushkey,
          appDisplayName: appDisplayName,
          deviceDisplayName: deviceDisplayName,
          kind: 'http',
          lang: lang,
          data: PusherData(url: gatewayUrl, format: format),
          profileTag: profileTag,
        ),
        append: true,
      );

  /// Removes a previously registered pusher by [appId] and [pushkey].
  Future<void> deletePusherByKey(String appId, String pushkey) =>
      _client.deletePusher(PusherId(appId: appId, pushkey: pushkey));

  /// Marks [roomId] as read up to its latest event. No-op when the room
  /// or its last event is unknown.
  Future<void> markRoomRead(String roomId) async {
    final room = _client.getRoomById(roomId);
    final lastEventId = room?.lastEvent?.eventId;
    if (room == null || lastEventId == null) return;
    await room.setReadMarker(lastEventId, mRead: lastEventId);
  }

  // ── Room accessors (notification rendering) ────────────────

  /// Whether [roomId] is known to the client.
  bool roomExists(String roomId) => _client.getRoomById(roomId) != null;

  /// The localized display name of [roomId], or null if unknown.
  String? roomDisplayName(String roomId) =>
      _client.getRoomById(roomId)?.getLocalizedDisplayname();

  /// Whether [roomId] is muted via its push rule state.
  bool roomMutesNotifications(String roomId) =>
      _client.getRoomById(roomId)?.pushRuleState == PushRuleState.dontNotify;

  /// Whether the current user has joined [roomId].
  bool isJoinedRoom(String roomId) =>
      _client.getRoomById(roomId)?.membership == Membership.join;

  /// Whether [roomId] is a direct chat.
  bool isDirectChatRoom(String roomId) =>
      _client.getRoomById(roomId)?.isDirectChat ?? false;

  /// The unread highlight count of [roomId].
  int highlightCountFor(String roomId) =>
      _client.getRoomById(roomId)?.highlightCount ?? 0;

  /// The unread notification count of [roomId].
  int unreadCountFor(String roomId) =>
      _client.getRoomById(roomId)?.notificationCount ?? 0;

  /// The avatar URL of [roomId], or null if unset or unknown.
  String? roomAvatarUrl(String roomId) =>
      _client.getRoomById(roomId)?.avatar?.toString();

  /// The event ID of the room's most recent event, or null.
  String? lastEventIdFor(String roomId) =>
      _client.getRoomById(roomId)?.lastEvent?.eventId;

  /// The number of rooms the current user is invited to.
  int get invitationCount =>
      _client.rooms.where((r) => r.membership == Membership.invite).length;

  /// The display name of [userId] in [roomId], or null if the room is
  /// unknown. Falls back to the Matrix ID when no display name is set.
  String? userDisplayName(String roomId, String userId) {
    final room = _client.getRoomById(roomId);
    return room?.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();
  }

  /// The avatar URL of [userId] in [roomId], or null.
  Uri? userAvatarUrl(String roomId, String userId) {
    final room = _client.getRoomById(roomId);
    return room?.unsafeGetUserFromMemoryOrFallback(userId).avatarUrl;
  }

  /// The body of [eventId] in [roomId], or null if unavailable.
  Future<String?> eventBodyFor(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    final event = await room.getEventById(eventId);
    return event?.body;
  }

  /// Sends [text] as a message to [roomId].
  Future<void> sendTextMessage(String roomId, String text) async {
    final room = _client.getRoomById(roomId);
    if (room != null) await room.sendTextEvent(text);
  }

  /// Marks [roomId] as read up to [eventId].
  Future<void> markRoomReadUpTo(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room != null) await room.setReadMarker(eventId, mRead: eventId);
  }

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
  int unreadNotificationCount() => _client.rooms
      .where((r) => r.notificationCount > 0)
      .fold<int>(0, (sum, r) => sum + r.notificationCount);

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

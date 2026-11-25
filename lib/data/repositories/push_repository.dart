import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/media_auth.dart' as media_auth;
import 'package:kohera/data/models/kohera_auth_exception.dart';
import 'package:kohera/data/models/kohera_decrypted_event.dart';
import 'package:kohera/data/models/kohera_push_notification.dart';
import 'package:kohera/data/models/kohera_sync_event.dart';
import 'package:kohera/data/models/kohera_sync_update.dart';
import 'package:kohera/data/resolvers/push_notification_resolver.dart';
import 'package:kohera/data/resolvers/sync_update_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/utils/event_preview.dart';
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

  /// Domain view of the sync stream for the notifications feature.
  Stream<KoheraSyncUpdate> get syncUpdates =>
      _client.onSync.stream.map(const SyncUpdateResolver().convert);

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
  ///
  /// Throws [KoheraAuthException] when the homeserver rejects the request.
  Future<void> markRoomReadUpTo(String roomId, String eventId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    try {
      await room.setReadMarker(eventId, mRead: eventId);
    } on MatrixException catch (e) {
      throw KoheraAuthException(e.errorMessage, errcode: e.errcode);
    }
  }

  // ── Push payload access ───────────────────────────────────────

  /// The SDK [Room] for [roomId], or null. Escape hatch for the platform push
  /// handlers that render notifications from raw room/event data.
  Room? getRoom(String roomId) => _client.getRoomById(roomId);

  /// Fetches a single event from the homeserver by [roomId]/[eventId].
  Future<MatrixEvent> getRoomEvent(String roomId, String eventId) =>
      _client.getOneRoomEvent(roomId, eventId);

  /// The total unread notification count across all rooms.
  int unreadNotificationCount() => _client.rooms
      .where((r) => r.notificationCount > 0)
      .fold<int>(0, (sum, r) => sum + r.notificationCount);

  // ── Sync ─────────────────────────────────────────────────────

  /// Performs a one-shot sync (used by platform push handlers to catch up
  /// after receiving a push).
  Future<void> oneShotSync() => _client.oneShotSync();

  // ── Notifications API ────────────────────────────────────────

  /// Fetches a page of notifications as domain models.
  ///
  /// Throws [KoheraAuthException] when the homeserver rejects the request
  /// (e.g. `M_UNKNOWN_TOKEN`).
  Future<({List<KoheraPushNotification> items, String? nextToken})>
      notifications({int limit = 30, String? from}) async {
    try {
      final response = await _client.getNotifications(limit: limit, from: from);
      const resolver = PushNotificationResolver();
      return (
        items: [for (final n in response.notifications) resolver.convert(n)],
        nextToken: response.nextToken,
      );
    } on MatrixException catch (e) {
      throw KoheraAuthException(e.errorMessage, errcode: e.errcode);
    }
  }

  /// Fetches a single event as a domain model.
  Future<KoheraSyncEvent> roomEvent(String roomId, String eventId) async {
    final event = await _client.getOneRoomEvent(roomId, eventId);
    return SyncUpdateResolver.convertEvent(event);
  }

  /// Decrypts [event] in [roomId], returning the decrypted payload, or null
  /// when the room is unknown or decryption is unavailable.
  Future<KoheraDecryptedEvent?> decryptEvent(
    String roomId,
    KoheraSyncEvent event,
  ) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return null;
    final sdkEvent = Event.fromMatrixEvent(_toMatrixEvent(event), room);
    final decrypted = await _client.encryption?.decryptRoomEvent(sdkEvent);
    if (decrypted == null) return null;
    return KoheraDecryptedEvent(
      type: decrypted.type,
      body: decrypted.body,
      content: decrypted.content,
    );
  }

  /// Builds the one-line notification preview for [event] in [roomId],
  /// using [decrypted] content when available.
  String notificationPreview({
    required String roomId,
    required KoheraSyncEvent event,
    KoheraDecryptedEvent? decrypted,
  }) {
    final room = _client.getRoomById(roomId);
    if (room == null) return '';
    final sdkEvent =
        Event.fromMatrixEvent(_toMatrixEvent(event, decrypted), room);
    return eventPreviewText(sdkEvent, room: room, myUserId: _client.userID);
  }

  MatrixEvent _toMatrixEvent(
    KoheraSyncEvent event, [
    KoheraDecryptedEvent? decrypted,
  ]) =>
      MatrixEvent(
        eventId: event.eventId ?? '',
        type: decrypted?.type ?? event.type,
        content: decrypted?.content ?? event.content,
        senderId: event.senderId,
        originServerTs: event.originServerTs ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Posts a read receipt for [eventId] in [roomId].
  ///
  /// Throws [KoheraAuthException] when the homeserver rejects the request.
  Future<void> postReceipt(
    String roomId,
    ReceiptType type,
    String eventId, {
    String? threadId,
  }) async {
    try {
      await _client.postReceipt(roomId, type, eventId, threadId: threadId);
    } on MatrixException catch (e) {
      throw KoheraAuthException(e.errorMessage, errcode: e.errcode);
    }
  }

  /// Posts an `m.read` receipt for [eventId] in [threadId] of [roomId].
  ///
  /// Throws [KoheraAuthException] when the homeserver rejects the request.
  Future<void> markThreadReadUpTo(
    String roomId,
    String threadId,
    String eventId,
  ) =>
      postReceipt(roomId, ReceiptType.mRead, eventId, threadId: threadId);

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

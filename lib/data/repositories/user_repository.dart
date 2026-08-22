import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/data/models/kohera_device.dart';
import 'package:kohera/data/models/kohera_device_key.dart';
import 'package:kohera/data/models/kohera_user_summary.dart';
import 'package:kohera/data/resolvers/device_resolver.dart';
import 'package:kohera/data/resolvers/user_summary_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/api.dart';

class UserRepository extends ChangeNotifier {
  UserRepository({
    required MatrixClientService clientService,
    PresenceService? presenceOverride,
  })  : _clientService = clientService,
        _presenceOverride = presenceOverride,
        _ownsPresence = presenceOverride == null;

  final MatrixClientService _clientService;
  final PresenceService? _presenceOverride;
  final bool _ownsPresence;
  PresenceService? _presence;
  bool _disposed = false;

  Client get _client => _clientService.client;

  void _onPresenceChanged() {
    if (!_disposed) notifyListeners();
  }

  // ── Presence ─────────────────────────────────────────────────

  /// Lazily binds the presence source and re-broadcasts its changes. In the
  /// app the [AccountSession] presence node is passed in and already syncing;
  /// standalone construction defers creation until presence is first read.
  PresenceService _ensurePresence() {
    final existing = _presence;
    if (existing != null) return existing;
    final presence = _presenceOverride ??
        PresenceService(matrixClientService: _clientService);
    presence.addListener(_onPresenceChanged);
    return _presence = presence;
  }

  /// The cached presence for [userId], or null when unknown.
  CachedPresence? presenceFor(String userId) =>
      _ensurePresence().presenceFor(userId);

  /// A human-readable presence line for [userId], or null when unknown.
  String? presenceLabel(String userId) =>
      _ensurePresence().presenceLabel(userId);

  // ── Domain model: user identity ──────────────────────────────

  String? get userId => _client.userID;
  String? get deviceId => _client.deviceID;

  /// The user's own homeserver URI, or null before login.
  Uri? get homeserver => _client.homeserver;

  /// Fetches the avatar URL from the logged-in user's own profile.
  Future<Uri?> fetchOwnAvatarUrl() async =>
      (await _client.fetchOwnProfile()).avatarUrl;

  /// Fetches the logged-in user's own display name and avatar URL.
  Future<({Uri? avatarUrl, String? displayName})> fetchOwnProfile() async {
    final profile = await _client.fetchOwnProfile();
    return (avatarUrl: profile.avatarUrl, displayName: profile.displayName);
  }

  /// Sets the logged-in user's display name.
  Future<void> setDisplayName(String name) async {
    final client = _client;
    await client.setProfileField(
      client.userID!,
      'displayname',
      {'displayname': name},
    );
  }

  /// Sets (or clears, when [bytes] is null) the logged-in user's avatar.
  Future<void> setOwnAvatar(Uint8List? bytes, String? name) async {
    await _client.setAvatar(
      bytes == null ? null : MatrixFile(bytes: bytes, name: name ?? ''),
    );
  }

  KoheraUserSummary? userSummary(String userId) {
    for (final room in _client.rooms) {
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      if (user.id == userId) {
        return const UserSummaryResolver()(user);
      }
    }
    return null;
  }

  // ── Domain model: device keys (DM partner) ───────────────────

  List<KoheraDeviceKey> deviceKeysFor(String userId) {
    final list = _client.userDeviceKeys[userId];
    final devices = list?.deviceKeys.values.toList() ?? [];
    return devices
        .map(
          (dk) => KoheraDeviceKey(
            deviceId: dk.deviceId,
            displayName: dk.deviceDisplayName,
            verified: dk.verified,
            blocked: dk.blocked,
          ),
        )
        .toList();
  }

  // ── Domain model: own devices ────────────────────────────────

  Future<List<KoheraDevice>> loadDevices() async {
    final client = _client;
    final devicesFuture = client.getDevices();
    final dehydratedIdFuture = _dehydratedDeviceId(client);
    final devices = await devicesFuture;
    final dehydratedId = await dehydratedIdFuture;
    if (devices == null) return [];

    final filtered = dehydratedId == null
        ? devices
        : devices.where((d) => d.deviceId != dehydratedId).toList();

    final currentDeviceId = client.deviceID;
    return filtered
        .map(
          (d) => const DeviceResolver()(
            d,
            isOwnDevice: d.deviceId == currentDeviceId,
            deviceKeys: _getDeviceKeys(client, d.deviceId),
          ),
        )
        .toList();
  }

  // ── Contacts ───────────────────────────────────────────────

  /// Returns user summaries for users the client has DM rooms with.
  List<KoheraUserSummary> knownContacts() {
    final seen = <String>{};
    final contacts = <KoheraUserSummary>[];
    for (final room in _client.rooms) {
      if (!room.isDirectChat) continue;
      final mxid = room.directChatMatrixID;
      if (mxid == null || !seen.add(mxid)) continue;
      contacts.add(
        KoheraUserSummary(
          userId: mxid,
          displayname: room.getLocalizedDisplayname(),
          avatarUrl: room.avatar?.toString(),
        ),
      );
    }
    return contacts;
  }

  /// Returns user summaries from joined group rooms, excluding
  /// [excludeMxids] and the client's own user ID.
  List<KoheraUserSummary> roomContacts({
    Set<String> excludeMxids = const {},
    int limit = 50,
  }) {
    final myId = _client.userID;
    final seen = <String>{...excludeMxids, ?myId};
    final contacts = <KoheraUserSummary>[];

    final groupRooms = _client.rooms
        .where((r) => !r.isDirectChat)
        .toList()
      ..sort((a, b) => (b.lastEvent?.originServerTs ?? DateTime(0))
          .compareTo(a.lastEvent?.originServerTs ?? DateTime(0)));

    for (final room in groupRooms) {
      if (contacts.length >= limit) break;
      for (final user in room.getParticipants()) {
        if (contacts.length >= limit) break;
        if (!seen.add(user.id)) continue;
        contacts.add(
          KoheraUserSummary(
            userId: user.id,
            displayname: user.displayName ?? user.id,
            avatarUrl: user.avatarUrl?.toString(),
          ),
        );
      }
    }
    return contacts;
  }

  // ── User operations (write path) ──────────────────────────────

  Future<void> ignoreUser(String userId, {bool leaveRooms = false}) =>
      _client.ignoreUser(userId, leaveRooms: leaveRooms);

  Future<void> unignoreUser(String userId) =>
      _client.unignoreUser(userId);

  /// Fetches the display name from a user's profile, or null if unavailable.
  Future<String?> fetchDisplayName(String userId) async =>
      (await _client.getProfileFromUserId(userId)).displayName;

  /// Fetches the avatar URL from a user's profile, or null if unavailable.
  Future<Uri?> fetchAvatarUrl(String userId) async {
    try {
      return (await _client.getProfileFromUserId(userId)).avatarUrl;
    } catch (_) {
      return null;
    }
  }

  Future<void> reportEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) =>
      _client.reportEvent(roomId, eventId, reason: reason);

  Future<void> renameDevice(String deviceId, String newName) =>
      _client.updateDevice(deviceId, displayName: newName);

  // ── Device operations (write path) ────────────────────────────

  Future<void> updateUserDeviceKeys() =>
      _client.updateUserDeviceKeys();

  /// Starts interactive verification for a specific device.
  ///
  /// Returns the SDK [KeyVerification] object that the caller uses to drive
  /// the verification dialog. This is the only method that returns an SDK
  /// type — it's an escape hatch for the E2EE verification UI flow.
  Future<KeyVerification?> startDeviceVerification(
    String userId,
    String deviceId,
  ) async {
    final dkList = _client.userDeviceKeys[userId];
    final dk = dkList?.deviceKeys[deviceId];
    if (dk == null) return null;
    return dk.startVerification();
  }

  Future<List<KoheraUserSummary>> searchUserDirectory(String term) async {
    final response = await _client.searchUserDirectory(term, limit: 20);
    return response.results
        .map(
          (p) => KoheraUserSummary(
            userId: p.userId,
            displayname: p.displayName ?? p.userId,
            avatarUrl: p.avatarUrl?.toString(),
          ),
        )
        .toList();
  }

  Future<void> removeDevice(String deviceId) async {
    final client = _client;
    await client.uiaRequestBackground(
      (auth) => client.deleteDevices([deviceId], auth: auth),
    );
  }

  Future<void> removeAllOtherDevices(List<String> deviceIds) async {
    final client = _client;
    await client.uiaRequestBackground(
      (auth) => client.deleteDevices(deviceIds, auth: auth),
    );
  }

  /// Refreshes device keys and starts verification for [deviceId].
  ///
  /// Returns the SDK [KeyVerification] to drive the verification dialog, or
  /// null if the device has no encryption keys. Like [startDeviceVerification]
  /// this is an escape hatch that returns an SDK type for the E2EE UI flow.
  Future<KeyVerification?> verifyDevice(String deviceId) async {
    final client = _client;
    final userId = client.userID;
    if (userId == null) return null;
    await client.updateUserDeviceKeys();
    final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (deviceKeys == null) return null;
    return deviceKeys.startVerification();
  }

  /// Permanently deactivates the signed-in account behind UIA.
  ///
  /// [erase] requests the homeserver to redact events and erase non-event
  /// data where possible. [idServer], when provided, is the identity server
  /// to unbind all 3PIDs from. The caller is responsible for dropping the
  /// local client afterwards (see [ClientManager.removeService]).
  Future<IdServerUnbindResult> deactivateAccount({
    bool erase = false,
    String? idServer,
  }) async {
    final client = _client;
    return client.uiaRequestBackground<IdServerUnbindResult>(
      (auth) => client.deactivateAccount(
        auth: auth,
        erase: erase,
        idServer: idServer,
      ),
    );
  }

  /// Toggles the blocked state of a device.
  Future<void> toggleBlockDevice(String deviceId) async {
    final client = _client;
    final userId = client.userID;
    if (userId == null) return;
    final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (deviceKeys == null) return;
    await deviceKeys.setBlocked(!deviceKeys.blocked);
  }

  // ── Ignored users ────────────────────────────────────────────

  List<String> get ignoredUsers => _client.ignoredUsers;

  // ── Sync stream ──────────────────────────────────────────────

  Stream<SyncUpdate> get onSync => _client.onSync.stream;

  // ── Helpers ──────────────────────────────────────────────────

  Future<String?> _dehydratedDeviceId(Client client) async {
    try {
      final device = await client.getDehydratedDevice();
      return device.deviceId;
    } catch (_) {
      return null;
    }
  }

  DeviceKeys? _getDeviceKeys(Client client, String deviceId) {
    final userId = client.userID;
    if (userId == null) return null;
    return client.userDeviceKeys[userId]?.deviceKeys[deviceId];
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final presence = _presence;
    if (presence != null) {
      presence.removeListener(_onPresenceChanged);
      if (_ownsPresence) presence.dispose();
    }
    super.dispose();
  }
}

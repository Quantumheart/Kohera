import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/data/models/kohera_device.dart';
import 'package:kohera/data/models/kohera_device_key.dart';
import 'package:kohera/data/models/kohera_user_summary.dart';
import 'package:kohera/data/resolvers/device_resolver.dart';
import 'package:kohera/data/resolvers/user_summary_resolver.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/api.dart';

class UserRepository extends ChangeNotifier {
  UserRepository({required MatrixService matrix}) : _matrix = matrix {
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

  // ── Domain model: user identity ──────────────────────────────

  String? get userId => _matrix.client.userID;
  String? get deviceId => _matrix.client.deviceID;

  /// Fetches the avatar URL from the logged-in user's own profile.
  Future<Uri?> fetchOwnAvatarUrl() async =>
      (await _matrix.client.fetchOwnProfile()).avatarUrl;

  KoheraUserSummary? userSummary(String userId) {
    for (final room in _matrix.client.rooms) {
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      if (user.id == userId) {
        return const UserSummaryResolver()(user);
      }
    }
    return null;
  }

  // ── Domain model: device keys (DM partner) ───────────────────

  List<KoheraDeviceKey> deviceKeysFor(String userId) {
    final list = _matrix.client.userDeviceKeys[userId];
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
    final client = _matrix.client;
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
    for (final room in _matrix.client.rooms) {
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
    final myId = _matrix.client.userID;
    final seen = <String>{...excludeMxids, ?myId};
    final contacts = <KoheraUserSummary>[];

    final groupRooms = _matrix.client.rooms
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
      _matrix.client.ignoreUser(userId, leaveRooms: leaveRooms);

  Future<void> unignoreUser(String userId) =>
      _matrix.client.unignoreUser(userId);

  Future<void> reportEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) =>
      _matrix.client.reportEvent(roomId, eventId, reason: reason);

  Future<void> renameDevice(String deviceId, String newName) =>
      _matrix.client.updateDevice(deviceId, displayName: newName);

  // ── Device operations (write path) ────────────────────────────

  Future<void> updateUserDeviceKeys() =>
      _matrix.client.updateUserDeviceKeys();

  /// Starts interactive verification for a specific device.
  ///
  /// Returns the SDK [KeyVerification] object that the caller uses to drive
  /// the verification dialog. This is the only method that returns an SDK
  /// type — it's an escape hatch for the E2EE verification UI flow.
  Future<KeyVerification?> startDeviceVerification(
    String userId,
    String deviceId,
  ) async {
    final dkList = _matrix.client.userDeviceKeys[userId];
    final dk = dkList?.deviceKeys[deviceId];
    if (dk == null) return null;
    return dk.startVerification();
  }

  Future<List<KoheraUserSummary>> searchUserDirectory(String term) async {
    final response = await _matrix.client.searchUserDirectory(term, limit: 20);
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
    final client = _matrix.client;
    await client.uiaRequestBackground(
      (auth) => client.deleteDevices([deviceId], auth: auth),
    );
  }

  Future<void> removeAllOtherDevices(List<String> deviceIds) async {
    final client = _matrix.client;
    await client.uiaRequestBackground(
      (auth) => client.deleteDevices(deviceIds, auth: auth),
    );
  }

  // ── Ignored users ────────────────────────────────────────────

  List<String> get ignoredUsers => _matrix.client.ignoredUsers;

  // ── Presence ─────────────────────────────────────────────────

  PresenceService get presence => _matrix.presence;

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
    _matrix.removeListener(_onMatrixChanged);
    super.dispose();
  }
}

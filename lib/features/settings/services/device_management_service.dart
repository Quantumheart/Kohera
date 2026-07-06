import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/settings/models/kohera_device.dart';
import 'package:kohera/features/settings/services/device_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/api.dart';

/// Wraps all Matrix SDK device management operations.
///
/// Screens use this service to avoid importing `package:matrix/matrix.dart`.
/// Device operations take `String deviceId` instead of SDK `Device` objects,
/// and [loadDevices] returns pre-converted [KoheraDevice] list.
class DeviceManagementService {
  DeviceManagementService({required this.matrix});

  final MatrixService matrix;

  /// Loads all devices (excluding dehydrated devices), converted to
  /// [KoheraDevice] with pre-computed display fields.
  Future<List<KoheraDevice>> loadDevices() async {
    final client = matrix.client;
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

  /// The current device ID, or `null`.
  String? get currentDeviceId => matrix.client.deviceID;

  /// Renames a device by ID.
  Future<void> renameDevice(String deviceId, String newName) async {
    await matrix.client.updateDevice(deviceId, displayName: newName);
  }

  /// Removes a single device by ID (with UIA handling).
  Future<void> removeDevice(String deviceId) async {
    final client = matrix.client;
    await client.uiaRequestBackground(
      (auth) => client.deleteDevices([deviceId], auth: auth),
    );
  }

  /// Removes multiple devices by ID (with UIA handling).
  Future<void> removeAllOtherDevices(List<String> deviceIds) async {
    final client = matrix.client;
    await client.uiaRequestBackground(
      (auth) => client.deleteDevices(deviceIds, auth: auth),
    );
  }

  /// Starts key verification for a device.
  ///
  /// Returns a [KoheraKeyVerification] to pass to `KeyVerificationDialog.show`,
  /// or `null` if the device has no encryption keys.
  Future<KoheraKeyVerification?> verifyDevice(String deviceId) async {
    final client = matrix.client;
    final userId = client.userID;
    if (userId == null) return null;

    await client.updateUserDeviceKeys();
    final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (deviceKeys == null) return null;

    final verification = await deviceKeys.startVerification();
    return KoheraKeyVerification(verification);
  }

  /// Toggles the blocked state of a device.
  Future<void> toggleBlockDevice(String deviceId) async {
    final client = matrix.client;
    final userId = client.userID;
    if (userId == null) return;

    final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (deviceKeys == null) return;

    await deviceKeys.setBlocked(!deviceKeys.blocked);
  }

  // ── Internal helpers ────────────────────────────────────────

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
}

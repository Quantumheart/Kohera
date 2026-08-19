import 'package:flutter/widgets.dart';

/// A Kohera-owned domain model representing a Matrix device with pre-computed
/// display fields.
///
/// This is the device model for the device settings screen. It carries no
/// `package:matrix/matrix.dart` dependency — the SDK `Device` (and optional
/// `DeviceKeys`) is converted to this type at the boundary in
/// `DevicesScreen` via [DeviceResolver]. The device list item widget only
/// ever sees this SDK-free type, so it needs no Matrix SDK import.
///
/// The display fields ([displayNameOrId], [platformLabel], [deviceIcon],
/// [lastActiveString]) are pre-computed once at the conversion boundary
/// rather than on every widget build.
@immutable
class KoheraDevice {
  const KoheraDevice({
    required this.deviceId,
    required this.displayName,
    required this.isOwnDevice,
    required this.isVerified,
    required this.isBlocked,
    required this.keys,
    required this.lastSeenTs,
    required this.displayNameOrId,
    required this.platformLabel,
    required this.deviceIcon,
    required this.lastActiveString,
  });

  /// The Matrix device ID (e.g. `ABCD12`).
  final String deviceId;

  /// The user-set device display name, or `null`.
  final String? displayName;

  /// Whether this is the current account's own device.
  final bool isOwnDevice;

  /// Whether the device is verified via the SDK's cross-signing trust chain.
  final bool isVerified;

  /// Whether the device is blocked from receiving encryption keys.
  final bool isBlocked;

  /// The device's key fingerprints as a `keyId → fingerprint` map
  /// (e.g. `{'ed25519:ABCD12': '...', 'curve25519:ABCD12': '...'}`), or
  /// `null` when no encryption keys are loaded for the device.
  final Map<String, String>? keys;

  /// The last-seen timestamp, or `null`.
  final DateTime? lastSeenTs;

  /// The user-friendly display name, falling back to the device ID.
  final String displayNameOrId;

  /// A platform label inferred from the display name, or `null`.
  final String? platformLabel;

  /// An appropriate icon based on the device display name.
  final IconData deviceIcon;

  /// A human-readable "last active" string (e.g. `Active now`, `5h ago`).
  final String lastActiveString;

  /// Whether encryption keys are loaded for this device.
  ///
  /// Used to gate the Verify/Block menu items. `true` when [keys] is non-null,
  /// mirroring the previous `deviceKeys != null` check.
  bool get hasDeviceKeys => keys != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraDevice && deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;

  @override
  String toString() =>
      'KoheraDevice(deviceId: $deviceId, displayName: $displayName, '
      'isOwnDevice: $isOwnDevice, isVerified: $isVerified, '
      'isBlocked: $isBlocked)';
}

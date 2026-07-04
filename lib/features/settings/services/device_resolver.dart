import 'package:kohera/core/extensions/device_extension.dart';
import 'package:kohera/features/settings/models/kohera_device.dart';
import 'package:matrix/matrix.dart';

/// Converts a Matrix SDK [Device] (with optional [DeviceKeys]) into a
/// UI-ready, SDK-free [KoheraDevice].
///
/// This resolver is the conversion boundary: it is the only place that imports
/// both the SDK-coupled [Device]/[DeviceKeys] and the SDK-free [KoheraDevice].
/// [DevicesScreen] calls it where it builds `DeviceListItem`s as
/// `const DeviceResolver()(device, isOwnDevice: true, deviceKeys: keys)`, so the
/// widget never touches a Matrix SDK type.
///
/// The display fields ([displayNameOrId], [platformLabel], [deviceIcon],
/// [lastActiveString]) are computed here via the existing [DeviceExtension]
/// helpers, so the platform/icon/last-active logic is not duplicated.
///
/// [isOwnDevice] is supplied by the screen depending on whether the device's
/// ID matches the active client's device ID.
class DeviceResolver {
  const DeviceResolver();

  KoheraDevice call(
    Device device, {
    required bool isOwnDevice,
    DeviceKeys? deviceKeys,
  }) {
    return KoheraDevice(
      deviceId: device.deviceId,
      displayName: device.displayName,
      isOwnDevice: isOwnDevice,
      isVerified: deviceKeys?.verified ?? false,
      isBlocked: deviceKeys?.blocked ?? false,
      keys: deviceKeys?.keys,
      lastSeenTs: device.lastSeenDate,
      displayNameOrId: device.displayNameOrId,
      platformLabel: device.platformLabel,
      deviceIcon: device.deviceIcon,
      lastActiveString: device.lastActiveString,
    );
  }
}

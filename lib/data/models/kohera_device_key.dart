import 'package:flutter/foundation.dart';

/// A Kohera-owned snapshot of a partner's device key for verification UI.
///
/// Carries no `package:matrix/matrix.dart` dependency; the conversion
/// boundary ([RoomDetailsController]) maps SDK `DeviceKeys` to this type.
@immutable
class KoheraDeviceKey {
  const KoheraDeviceKey({
    required this.deviceId,
    required this.displayName,
    required this.verified,
    required this.blocked,
  });

  final String? deviceId;
  final String? displayName;
  final bool verified;
  final bool blocked;
}

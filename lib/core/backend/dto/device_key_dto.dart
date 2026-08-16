// coverage:ignore-file

import 'package:kohera/core/backend/dto/dto.dart';
import 'package:matrix/matrix.dart';

class DeviceKeyDto implements Dto {
  final String userId;
  final String deviceId;
  final String? deviceDisplayName;
  final Map<String, String> keys;
  final bool verified;
  final bool blocked;
  final String? ed25519Key;
  final String? curve25519Key;

  const DeviceKeyDto({
    required this.userId,
    required this.deviceId,
    required this.verified,
    required this.blocked,
    this.deviceDisplayName,
    this.keys = const {},
    this.ed25519Key,
    this.curve25519Key,
  });

  factory DeviceKeyDto.fromSdk(DeviceKeys dk) => DeviceKeyDto(
        userId: dk.userId,
        deviceId: dk.deviceId ?? '',
        deviceDisplayName: dk.deviceDisplayName,
        keys: dk.keys,
        verified: dk.verified,
        blocked: dk.blocked,
        ed25519Key: dk.ed25519Key,
        curve25519Key: dk.curve25519Key,
      );

  @override
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'deviceId': deviceId,
        'deviceDisplayName': deviceDisplayName,
        'keys': keys,
        'verified': verified,
        'blocked': blocked,
        'ed25519Key': ed25519Key,
        'curve25519Key': curve25519Key,
      };

  factory DeviceKeyDto.fromMap(Map<String, dynamic> m) => DeviceKeyDto(
        userId: m['userId'] as String,
        deviceId: m['deviceId'] as String,
        deviceDisplayName: m['deviceDisplayName'] as String?,
        keys: (m['keys'] as Map?)?.cast<String, String>() ?? const {},
        verified: m['verified'] as bool,
        blocked: m['blocked'] as bool,
        ed25519Key: m['ed25519Key'] as String?,
        curve25519Key: m['curve25519Key'] as String?,
      );
}

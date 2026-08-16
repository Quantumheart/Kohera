// coverage:ignore-file

import 'package:kohera/core/backend/dto/dto.dart';

class VerificationDto implements Dto {
  final String state;
  final String? method;
  final String? deviceId;

  const VerificationDto({
    required this.state,
    this.method,
    this.deviceId,
  });

  @override
  Map<String, dynamic> toMap() => {
        'state': state,
        'method': method,
        'deviceId': deviceId,
      };

  factory VerificationDto.fromMap(Map<String, dynamic> m) => VerificationDto(
        state: m['state'] as String,
        method: m['method'] as String?,
        deviceId: m['deviceId'] as String?,
      );
}

// coverage:ignore-file

import 'package:kohera/core/backend/dto.dart';
import 'package:matrix/matrix.dart';

class AccountDto implements Dto {
  final String clientName;
  final String userId;
  final String deviceId;
  final String homeserver;
  final String displayName;
  final String? avatarMxc;
  final bool isLoggedIn;

  const AccountDto({
    required this.clientName,
    required this.userId,
    required this.deviceId,
    required this.homeserver,
    required this.displayName,
    required this.isLoggedIn,
    this.avatarMxc,
  });

  factory AccountDto.fromSdk(Client client) => AccountDto(
        clientName: client.clientName,
        userId: client.userID ?? '',
        deviceId: client.deviceID ?? '',
        homeserver: client.homeserver?.toString() ?? '',
        displayName: client.userID ?? '',
        isLoggedIn: client.isLogged(),
      );

  @override
  Map<String, dynamic> toMap() => {
        'clientName': clientName,
        'userId': userId,
        'deviceId': deviceId,
        'homeserver': homeserver,
        'displayName': displayName,
        'avatarMxc': avatarMxc,
        'isLoggedIn': isLoggedIn,
      };

  factory AccountDto.fromMap(Map<String, dynamic> m) => AccountDto(
        clientName: m['clientName'] as String,
        userId: m['userId'] as String,
        deviceId: m['deviceId'] as String,
        homeserver: m['homeserver'] as String,
        displayName: m['displayName'] as String,
        avatarMxc: m['avatarMxc'] as String?,
        isLoggedIn: m['isLoggedIn'] as bool,
      );
}
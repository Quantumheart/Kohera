// coverage:ignore-file

import 'package:kohera/core/backend/dto/dto.dart';
import 'package:matrix/matrix.dart';

class UserDto implements Dto {
  final String userId;
  final String displayName;
  final String? avatarMxc;

  const UserDto({
    required this.userId,
    required this.displayName,
    this.avatarMxc,
  });

  factory UserDto.fromSdk(User user) => UserDto(
        userId: user.id,
        displayName: user.displayName ?? user.id,
        avatarMxc: user.avatarUrl?.toString(),
      );

  factory UserDto.fromProfile(Profile profile) => UserDto(
        userId: profile.userId,
        displayName: profile.displayName ?? profile.userId,
        avatarMxc: profile.avatarUrl?.toString(),
      );

  @override
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'displayName': displayName,
        'avatarMxc': avatarMxc,
      };

  factory UserDto.fromMap(Map<String, dynamic> m) => UserDto(
        userId: m['userId'] as String,
        displayName: m['displayName'] as String,
        avatarMxc: m['avatarMxc'] as String?,
      );
}

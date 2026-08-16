// coverage:ignore-file

import 'package:kohera/core/backend/dto/dto.dart';
import 'package:matrix/matrix.dart';

class MemberDto implements Dto {
  final String userId;
  final String displayName;
  final String? avatarMxc;
  final int powerLevel;

  const MemberDto({
    required this.userId,
    required this.displayName,
    required this.powerLevel,
    this.avatarMxc,
  });

  factory MemberDto.fromSdk(User user, int powerLevel) => MemberDto(
        userId: user.id,
        displayName: user.displayName ?? user.id,
        avatarMxc: user.avatarUrl?.toString(),
        powerLevel: powerLevel,
      );

  @override
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'displayName': displayName,
        'avatarMxc': avatarMxc,
        'powerLevel': powerLevel,
      };

  factory MemberDto.fromMap(Map<String, dynamic> m) => MemberDto(
        userId: m['userId'] as String,
        displayName: m['displayName'] as String,
        avatarMxc: m['avatarMxc'] as String?,
        powerLevel: m['powerLevel'] as int,
      );
}

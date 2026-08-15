// coverage:ignore-file

import 'package:kohera/core/backend/dto.dart';
import 'package:matrix/matrix.dart';

class RoomDto implements Dto {
  final String roomId;
  final String name;
  final String displayName;
  final String? canonicalAlias;
  final String? avatarMxc;
  final String? topic;
  final bool encrypted;
  final bool isDirect;
  final String membership;
  final int unreadCount;
  final int notificationCount;
  final int highlightCount;
  final String? lastEventId;
  final int? lastEventTs;
  final bool muted;
  final String pushRuleState;

  const RoomDto({
    required this.roomId,
    required this.name,
    required this.displayName,
    required this.encrypted,
    required this.isDirect,
    required this.membership,
    required this.unreadCount,
    required this.notificationCount,
    required this.highlightCount,
    required this.muted,
    required this.pushRuleState,
    this.canonicalAlias,
    this.avatarMxc,
    this.topic,
    this.lastEventId,
    this.lastEventTs,
  });

  factory RoomDto.fromSdk(Room room) => RoomDto(
        roomId: room.id,
        name: room.name,
        displayName: room.getLocalizedDisplayname(),
        canonicalAlias: room.canonicalAlias,
        avatarMxc: room.avatar?.toString(),
        topic: room.topic,
        encrypted: room.encrypted,
        isDirect: room.isDirectChat,
        membership: room.membership.toString(),
        unreadCount: room.notificationCount,
        notificationCount: room.notificationCount,
        highlightCount: room.highlightCount,
        lastEventId: room.lastEvent?.eventId,
        lastEventTs: room.lastEvent?.originServerTs.millisecondsSinceEpoch,
        muted: room.pushRuleState == PushRuleState.mentionsOnly ||
            room.pushRuleState == PushRuleState.dontNotify,
        pushRuleState: room.pushRuleState.toString(),
      );

  @override
  Map<String, dynamic> toMap() => {
        'roomId': roomId,
        'name': name,
        'displayName': displayName,
        'canonicalAlias': canonicalAlias,
        'avatarMxc': avatarMxc,
        'topic': topic,
        'encrypted': encrypted,
        'isDirect': isDirect,
        'membership': membership,
        'unreadCount': unreadCount,
        'notificationCount': notificationCount,
        'highlightCount': highlightCount,
        'lastEventId': lastEventId,
        'lastEventTs': lastEventTs,
        'muted': muted,
        'pushRuleState': pushRuleState,
      };

  factory RoomDto.fromMap(Map<String, dynamic> m) => RoomDto(
        roomId: m['roomId'] as String,
        name: m['name'] as String,
        displayName: m['displayName'] as String,
        canonicalAlias: m['canonicalAlias'] as String?,
        avatarMxc: m['avatarMxc'] as String?,
        topic: m['topic'] as String?,
        encrypted: m['encrypted'] as bool,
        isDirect: m['isDirect'] as bool,
        membership: m['membership'] as String,
        unreadCount: m['unreadCount'] as int,
        notificationCount: m['notificationCount'] as int,
        highlightCount: m['highlightCount'] as int,
        lastEventId: m['lastEventId'] as String?,
        lastEventTs: m['lastEventTs'] as int?,
        muted: m['muted'] as bool,
        pushRuleState: m['pushRuleState'] as String,
      );
}

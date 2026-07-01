import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_state_event_text.dart';
import 'package:matrix/matrix.dart';

class StateEventResolver {
  const StateEventResolver();

  KoheraStateEventText call(Event event) {
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();

    switch (event.type) {
      case EventTypes.RoomMember:
        return _resolveMember(event, sender);
      case EventTypes.RoomName:
        return _resolveRoomName(event, sender);
      case EventTypes.RoomTopic:
        return _resolveRoomTopic(event, sender);
      case EventTypes.RoomAvatar:
        return _resolveRoomAvatar(event, sender);
      case EventTypes.RoomTombstone:
        return _resolveTombstone(event);
      default:
        return KoheraStateEventText(
          icon: Icons.info_outline,
          text: 'Room updated',
          timestamp: event.originServerTs,
        );
    }
  }

  KoheraStateEventText _resolveRoomName(Event event, String sender) {
    final name = event.content.tryGet<String>('name') ?? '';
    return KoheraStateEventText(
      icon: Icons.edit_outlined,
      text: name.isEmpty
          ? '$sender removed the room name'
          : "$sender changed the room name to '$name'",
      timestamp: event.originServerTs,
    );
  }

  KoheraStateEventText _resolveRoomTopic(Event event, String sender) {
    final topic = event.content.tryGet<String>('topic') ?? '';
    return KoheraStateEventText(
      icon: Icons.edit_outlined,
      text: topic.isEmpty
          ? '$sender removed the room topic'
          : "$sender changed the topic to '$topic'",
      timestamp: event.originServerTs,
    );
  }

  KoheraStateEventText _resolveRoomAvatar(Event event, String sender) {
    return KoheraStateEventText(
      icon: Icons.image_outlined,
      text: '$sender changed the room avatar',
      timestamp: event.originServerTs,
    );
  }

  KoheraStateEventText _resolveTombstone(Event event) {
    final body = event.content.tryGet<String>('body');
    final replacement = event.content.tryGet<String>('replacement_room');
    final suffix = (body != null && body.isNotEmpty) ? ' $body' : '';
    return KoheraStateEventText(
      icon: Icons.upgrade_rounded,
      text: 'This room has been upgraded.$suffix Tap to open the new room.',
      timestamp: event.originServerTs,
      replacementRoomId: (replacement != null && replacement.isNotEmpty)
          ? replacement
          : null,
    );
  }

  KoheraStateEventText _resolveMember(Event event, String sender) {
    final membership = event.content.tryGet<String>('membership');
    final prevMembership = event.prevContent?.tryGet<String>('membership');
    final target = event.stateKey;
    final targetUser = target != null
        ? event.room.unsafeGetUserFromMemoryOrFallback(target)
        : null;
    final targetName = targetUser?.calcDisplayname() ?? target ?? 'Someone';
    final reason = event.content.tryGet<String>('reason');

    switch (membership) {
      case 'invite':
        return KoheraStateEventText(
          icon: Icons.person_add_alt_1_outlined,
          text: '$targetName was invited by $sender',
          timestamp: event.originServerTs,
        );
      case 'join':
        if (prevMembership == 'join') {
          final prevDisplay = event.prevContent?.tryGet<String>('displayname');
          final newDisplay = event.content.tryGet<String>('displayname');
          if (prevDisplay != newDisplay) {
            final subject = (prevDisplay != null && prevDisplay.isNotEmpty)
                ? prevDisplay
                : (target != null
                      ? target.replaceFirst('@', '').split(':').first
                      : targetName);
            return KoheraStateEventText(
              icon: Icons.badge_outlined,
              text: newDisplay == null || newDisplay.isEmpty
                  ? '$subject removed their display name'
                  : "$subject changed their display name to '$newDisplay'",
              timestamp: event.originServerTs,
            );
          }
          final prevAvatar = event.prevContent?.tryGet<String>('avatar_url');
          final newAvatar = event.content.tryGet<String>('avatar_url');
          if (prevAvatar != newAvatar) {
            return KoheraStateEventText(
              icon: Icons.image_outlined,
              text: '$targetName changed their avatar',
              timestamp: event.originServerTs,
            );
          }
          return KoheraStateEventText(
            icon: Icons.login_rounded,
            text: '$targetName updated their profile',
            timestamp: event.originServerTs,
          );
        }
        return KoheraStateEventText(
          icon: Icons.login_rounded,
          text: '$targetName joined',
          timestamp: event.originServerTs,
        );
      case 'leave':
        if (target == event.senderId) {
          if (prevMembership == 'invite') {
            return KoheraStateEventText(
              icon: Icons.cancel_outlined,
              text: '$targetName rejected the invitation',
              timestamp: event.originServerTs,
            );
          }
          return KoheraStateEventText(
            icon: Icons.logout_rounded,
            text: '$targetName left',
            timestamp: event.originServerTs,
          );
        }
        final reasonSuffix =
            (reason != null && reason.isNotEmpty) ? ' ($reason)' : '';
        return KoheraStateEventText(
          icon: Icons.person_remove_outlined,
          text: '$targetName was kicked by $sender$reasonSuffix',
          timestamp: event.originServerTs,
        );
      case 'ban':
        final reasonSuffix =
            (reason != null && reason.isNotEmpty) ? ' ($reason)' : '';
        return KoheraStateEventText(
          icon: Icons.block_rounded,
          text: '$targetName was banned by $sender$reasonSuffix',
          timestamp: event.originServerTs,
        );
      case 'knock':
        return KoheraStateEventText(
          icon: Icons.front_hand_outlined,
          text: '$targetName requested to join',
          timestamp: event.originServerTs,
        );
      default:
        return KoheraStateEventText(
          icon: Icons.info_outline,
          text: 'Membership changed',
          timestamp: event.originServerTs,
        );
    }
  }
}

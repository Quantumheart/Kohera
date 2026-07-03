import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/features/chat/services/media_content_resolver.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:kohera/features/chat/services/reaction_resolver.dart';
import 'package:kohera/features/chat/services/sdk_media_controller.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';
import 'package:kohera/features/chat/widgets/audio_bubble.dart';
import 'package:kohera/features/chat/widgets/delete_event_dialog.dart';
import 'package:kohera/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:kohera/features/chat/widgets/file_bubble.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/image_bubble.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/message_action_sheet.dart';
import 'package:kohera/features/chat/widgets/message_bubble.dart';
import 'package:kohera/features/chat/widgets/message_bubble_context_menu.dart';
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:kohera/features/chat/widgets/read_receipts.dart';
import 'package:kohera/features/chat/widgets/reply_preview_host.dart';
import 'package:kohera/features/chat/widgets/swipeable_message.dart';
import 'package:kohera/features/chat/widgets/thread_indicator_chip.dart';
import 'package:kohera/features/chat/widgets/video_bubble.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/features/rooms/widgets/member_sheet_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

const _msgtypeImage = 'm.image';
const _msgtypeAudio = 'm.audio';
const _msgtypeVideo = 'm.video';
const _msgtypeFile = 'm.file';

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({
    required this.event,
    required this.isMe,
    required this.isFirst,
    required this.isMobile,
    required this.timeline,
    required this.client,
    required this.onToggleReaction,
    this.highlightedEventId,
    this.receiptMap = const {},
    this.onReply,
    this.onEdit,
    this.onPin,
    this.onTapReply,
    this.onReplyInThread,
    this.onOpenThread,
    this.onForward,
    this.inThread = false,
    super.key,
  });

  final Event event;
  final bool isMe;
  final bool isFirst;
  final bool isMobile;
  final Timeline? timeline;
  final Client client;
  final String? highlightedEventId;
  final Map<String, List<KoheraReadReceipt>> receiptMap;
  final void Function(Event event)? onReply;
  final void Function(Event event)? onEdit;
  final Future<void> Function(Event event)? onPin;
  final void Function(Event event)? onTapReply;
  final void Function(Event event)? onReplyInThread;
  final void Function(Event event)? onOpenThread;
  final void Function(Event event)? onForward;
  final bool inThread;
  final Future<void> Function(Event event, String emoji) onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final isRedacted = event.redacted;
    final room = event.room;
    final isPinned = room.pinnedEventIds.contains(event.eventId);
    final canPin = !isRedacted &&
        room.canChangeStateEvent('m.room.pinned_events');

    final message = const MessageDisplayResolver()(event, timeline: timeline);

    final hasReactions = timeline != null &&
        event.hasAggregatedEvents(timeline!, RelationshipTypes.reaction);
    final hasThread = !inThread &&
        timeline != null &&
        event.hasAggregatedEvents(timeline!, RelationshipTypes.thread);
    final threadReplyCount = hasThread
        ? event.aggregatedEvents(timeline!, RelationshipTypes.thread).length
        : 0;
    final receipts = receiptMap[event.eventId]
        ?.where((r) => r.user.userId != event.senderId)
        .toList();

    Widget? reactionBubble;
    if (hasReactions) {
      final reactionList = const ReactionResolver().resolve(
        event,
        timeline!,
        myUserId: client.userID ?? '',
      );
      reactionBubble = ReactionChips(
        reactions: reactionList,
        isMe: isMe,
        avatarResolver: context.read<MatrixService>().avatarResolver,
        onToggle: (emoji) => onToggleReaction(event, emoji),
      );
    }

    Widget? subBubble;
    if (receipts != null && receipts.isNotEmpty) {
      subBubble = ReadReceiptsRow(
        receipts: receipts,
        avatarResolver: context.read<MatrixService>().avatarResolver,
        isMe: isMe,
      );
    }

    Widget? replyPreview;
    if (message.replyEventId != null && !isRedacted && timeline != null) {
      replyPreview = ReplyPreviewHost(
        replyEvent: event,
        timeline: timeline,
        isMe: isMe,
        onParentTap: onTapReply,
      );
    }

    final mediaContent = const MediaContentResolver()(event);
    final mediaController = SdkMediaController(event);
    Widget? mediaBody;
    if (!isRedacted) {
      switch (message.messageType) {
        case _msgtypeImage:
          mediaBody = ImageBubble(
            media: mediaContent,
            controller: mediaController,
            avatarResolver: context.read<MatrixService>().avatarResolver,
          );
        case _msgtypeAudio:
          mediaBody = AudioBubble(
            media: mediaContent,
            controller: mediaController,
            isMe: isMe,
          );
        case _msgtypeVideo:
          mediaBody = VideoBubble(
            media: mediaContent,
            controller: mediaController,
            isMe: isMe,
            avatarResolver: context.read<MatrixService>().avatarResolver,
          );
        case _msgtypeFile:
          mediaBody = FileBubble(
            media: mediaContent,
            controller: mediaController,
            isMe: isMe,
          );
      }
    }

    final Widget content = MessageBubble(
      message: message,
      isMe: isMe,
      isFirst: isFirst,
      highlighted: event.eventId == highlightedEventId,
      isPinned: isPinned,
      avatarResolver: context.read<MatrixService>().avatarResolver,
      htmlBuilder: (html, style) => HtmlMessageText(
        html: html,
        style: style,
        isMe: isMe,
        room: room,
      ),
      replyPreview: replyPreview,
      mediaBody: mediaBody,
      onOpenContextMenu: isRedacted
          ? null
          : (position) => _openContextMenu(context, position, isPinned, canPin),
      onTapSender: () => _showSenderSheet(context),
      onReply: isRedacted ? null : () => onReply?.call(event),
      onEdit: !isRedacted && isMe ? () => onEdit?.call(event) : null,
      onDelete: !isRedacted && event.canRedact
          ? () => confirmAndDeleteEvent(context, event)
          : null,
      onReact: isRedacted
          ? null
          : () => showEmojiPickerSheet(
                context,
                (emoji) => onToggleReaction(event, emoji),
              ),
      onQuickReact: isRedacted
          ? null
          : (emoji) => onToggleReaction(event, emoji),
      onPin: canPin ? () => onPin?.call(event) : null,
      onReplyInThread:
          isRedacted || inThread ? null : () => onReplyInThread?.call(event),
      onForward: isRedacted || onForward == null
          ? null
          : () => onForward!(event),
      reactionBubble: reactionBubble,
      subBubble: subBubble,
      threadIndicator: hasThread
          ? ThreadIndicatorChip(
              replyCount: threadReplyCount,
              isMe: isMe,
              unreadCount: threadUnreadCountFor(
                root: event,
                timeline: timeline!,
                room: room,
                myUserId: client.userID ?? '',
              ),
              onTap: () => onOpenThread?.call(event),
            )
          : null,
    );

    if (isMobile) {
      return SwipeableMessage(
        onReply: () => onReply?.call(event),
        child: LongPressWrapper(
          onLongPress: (rect) =>
              _showMobileActions(context, rect, isPinned, canPin),
          child: content,
        ),
      );
    }
    return content;
  }

  void _openContextMenu(
    BuildContext context,
    Offset position,
    bool isPinned,
    bool canPin,
  ) {
    unawaited(showMessageContextMenu(
      context,
      event: event,
      isMe: isMe,
      isPinned: isPinned,
      timeline: timeline,
      position: position,
      onReply: isRedactedSafe ? null : () => onReply?.call(event),
      onEdit: !isRedactedSafe && isMe ? () => onEdit?.call(event) : null,
      onReact: isRedactedSafe
          ? null
          : () => showEmojiPickerSheet(
                context,
                (emoji) => onToggleReaction(event, emoji),
              ),
      onPin: canPin ? () => onPin?.call(event) : null,
      onDelete: !isRedactedSafe && event.canRedact
          ? () => confirmAndDeleteEvent(context, event)
          : null,
      onReplyInThread:
          isRedactedSafe || inThread ? null : () => onReplyInThread?.call(event),
      onForward: isRedactedSafe || onForward == null
          ? null
          : () => onForward!(event),
    ),);
  }

  bool get isRedactedSafe => event.redacted;

  void _showSenderSheet(BuildContext context) {
    final sender = event.senderFromMemoryOrFallback;
    final room = event.room;
    final client = room.client;
    final isMe = sender.id == client.userID;
    final ownLevel = room.getPowerLevelByUserId(client.userID ?? '');
    final member = KoheraRoomMember(
      userId: sender.id,
      displayname: sender.calcDisplayname(),
      avatarUrl: sender.avatarUrl?.toString(),
      membership: sender.membership.name,
      powerLevel: room.getPowerLevelByUserId(sender.id),
    );
    unawaited(showMemberSheetDialog(
      context,
      member: member,
      isMe: isMe,
      ownLevel: ownLevel,
      canChangeRole: !isMe && room.canChangePowerLevel && member.powerLevel < ownLevel,
      canKick: !isMe && room.canKick && member.powerLevel < ownLevel && !member.isBanned,
      canBan: !isMe && room.canBan && member.powerLevel < ownLevel && !member.isBanned,
      avatarResolver: context.read<MatrixService>().avatarResolver,
      presence: context.read<MatrixService>().presence,
      onStartDm: isMe
          ? null
          : () async {
              final dmRoomId = await client.startDirectChat(
                member.userId,
                enableEncryption: true,
              );
              if (client.getRoomById(dmRoomId) == null) {
                await client
                    .waitForRoomInSync(dmRoomId, join: true)
                    .timeout(const Duration(seconds: 30));
              }
              if (!context.mounted) return;
              context.read<SelectionService>().selectRoom(dmRoomId);
              context.goNamed(
                Routes.room,
                pathParameters: {RouteParams.roomId: dmRoomId},
              );
            },
      onRoleChange: (level) => PowerLevelService.update(
        room,
        PowerLevelPatch(users: {member.userId: level}),
      ),
      onKick: (reason) => client.kick(room.id, member.userId, reason: reason),
      onBan: (reason) => client.ban(room.id, member.userId, reason: reason),
      onUnban: () => client.unban(room.id, member.userId),
    ),);
  }

  void _showMobileActions(
    BuildContext context,
    Rect bubbleRect,
    bool isPinned,
    bool canPin,
  ) {
    if (event.redacted) return;

    final cs = Theme.of(context).colorScheme;
    final List<MessageAction> actions;
    if (event.status.isError) {
      actions = <MessageAction>[
        MessageAction(
          label: 'Retry sending',
          icon: Icons.refresh_rounded,
          onTap: () async {
            try {
              await event.sendAgain();
            } catch (e) {
              debugPrint('[Kohera] outbox: retry from menu failed: $e');
            }
          },
        ),
        MessageAction(
          label: 'Discard message',
          icon: Icons.delete_outline_rounded,
          onTap: () async {
            try {
              await event.cancelSend();
            } catch (e) {
              debugPrint('[Kohera] outbox: discard from menu failed: $e');
            }
          },
          color: cs.error,
        ),
      ];
    } else {
      actions = <MessageAction>[
        MessageAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          onTap: () => onReply?.call(event),
        ),
        if (!inThread && onReplyInThread != null)
          MessageAction(
            label: 'Reply in thread',
            icon: Icons.forum_outlined,
            onTap: () => onReplyInThread?.call(event),
          ),
        if (onForward != null)
          MessageAction(
            label: 'Forward',
            icon: Icons.forward_rounded,
            onTap: () => onForward!(event),
          ),
        if (isMe)
          MessageAction(
            label: 'Edit',
            icon: Icons.edit_rounded,
            onTap: () => onEdit?.call(event),
          ),
        MessageAction(
          label: 'React',
          icon: Icons.add_reaction_outlined,
          onTap: () => showEmojiPickerSheet(
            context,
            (emoji) => onToggleReaction(event, emoji),
          ),
        ),
        if (canPin)
          MessageAction(
            label: isPinned ? 'Unpin' : 'Pin',
            icon: isPinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            onTap: () => onPin?.call(event),
          ),
        MessageAction(
          label: 'Copy',
          icon: Icons.copy_rounded,
          onTap: () {
            final displayEvent = timeline != null
                ? event.getDisplayEvent(timeline!)
                : event;
            unawaited(
              Clipboard.setData(
                ClipboardData(text: stripReplyFallback(displayEvent.body)),
              ),
            );
          },
        ),
        if (event.canRedact)
          MessageAction(
            label: isMe ? 'Delete' : 'Remove',
            icon: Icons.delete_outline_rounded,
            onTap: () => confirmAndDeleteEvent(context, event),
            color: cs.error,
          ),
      ];
    }

    showMessageActionSheet(
      context: context,
      event: event,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      timeline: timeline,
      onQuickReact: (emoji) => onToggleReaction(event, emoji),
    );
  }
}

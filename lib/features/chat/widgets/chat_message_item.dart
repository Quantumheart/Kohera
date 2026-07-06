import 'package:flutter/material.dart';
import 'package:kohera/features/chat/models/kohera_media_content.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/models/kohera_read_receipt.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';
import 'package:kohera/features/chat/widgets/audio_bubble.dart';
import 'package:kohera/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:kohera/features/chat/widgets/file_bubble.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/image_bubble.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/message_bubble.dart';
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:kohera/features/chat/widgets/read_receipts.dart';
import 'package:kohera/features/chat/widgets/swipeable_message.dart';
import 'package:kohera/features/chat/widgets/thread_indicator_chip.dart';
import 'package:kohera/features/chat/widgets/video_bubble.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_controller.dart';
import 'package:kohera/shared/services/media_resolver.dart';

const _msgtypeImage = 'm.image';
const _msgtypeAudio = 'm.audio';
const _msgtypeVideo = 'm.video';
const _msgtypeFile = 'm.file';

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({
    required this.message,
    required this.reactions,
    required this.media,
    required this.mediaController,
    required this.replyPreview,
    required this.isMe,
    required this.isFirst,
    required this.isMobile,
    required this.isPinned,
    required this.canPin,
    required this.canRedact,
    required this.hasThread,
    required this.threadReplyCount,
    required this.threadUnreadCount,
    required this.inThread,
    required this.highlightedEventId,
    required this.receiptMap,
    required this.avatarResolver,
    required this.mediaResolver,
    required this.mentionResolver,
    required this.onToggleReaction,
    this.onReply,
    this.onEdit,
    this.onPin,
    this.onReplyInThread,
    this.onOpenThread,
    this.onForward,
    this.onDelete,
    this.onTapSender,
    this.onRetrySend,
    this.onDiscardSend,
    this.onOpenContextMenu,
    this.onShowMobileActions,
    this.onTapReply,
    super.key,
  });

  final KoheraMessageDisplay message;
  final KoheraReactionList? reactions;
  final KoheraMediaContent? media;
  final MediaController? mediaController;
  final Widget? replyPreview;
  final bool isMe;
  final bool isFirst;
  final bool isMobile;
  final bool isPinned;
  final bool canPin;
  final bool canRedact;
  final bool hasThread;
  final int threadReplyCount;
  final int threadUnreadCount;
  final bool inThread;
  final String? highlightedEventId;
  final Map<String, List<KoheraReadReceipt>> receiptMap;
  final AvatarResolver avatarResolver;
  final MediaResolver mediaResolver;
  final MentionDisplayNameResolver mentionResolver;
  final Future<void> Function(String emoji) onToggleReaction;

  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;
  final VoidCallback? onReplyInThread;
  final VoidCallback? onOpenThread;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final VoidCallback? onTapSender;
  final VoidCallback? onRetrySend;
  final VoidCallback? onDiscardSend;
  final void Function(Offset position)? onOpenContextMenu;
  final void Function(Rect rect)? onShowMobileActions;
  final void Function(String messageId)? onTapReply;

  @override
  Widget build(BuildContext context) {
    final isRedacted = message.isRedacted;

    final receipts =
        receiptMap[message.eventId]?.where((r) => r.user.userId != message.senderId).toList();

    Widget? reactionBubble;
    if (reactions != null && reactions!.isNotEmpty) {
      reactionBubble = ReactionChips(
        reactions: reactions!,
        isMe: isMe,
        avatarResolver: avatarResolver,
        onToggle: onToggleReaction,
      );
    }

    Widget? subBubble;
    if (receipts != null && receipts.isNotEmpty) {
      subBubble = ReadReceiptsRow(
        receipts: receipts,
        avatarResolver: avatarResolver,
        isMe: isMe,
      );
    }

    Widget? mediaBody;
    if (!isRedacted && media != null && mediaController != null) {
      switch (message.messageType) {
        case _msgtypeImage:
          mediaBody = ImageBubble(
            media: media!,
            controller: mediaController!,
            avatarResolver: avatarResolver,
          );
        case _msgtypeAudio:
          mediaBody = AudioBubble(
            media: media!,
            controller: mediaController!,
            isMe: isMe,
          );
        case _msgtypeVideo:
          mediaBody = VideoBubble(
            media: media!,
            controller: mediaController!,
            isMe: isMe,
            avatarResolver: avatarResolver,
          );
        case _msgtypeFile:
          mediaBody = FileBubble(
            media: media!,
            controller: mediaController!,
            isMe: isMe,
          );
      }
    }

    final showThread = hasThread && !inThread;

    final Widget content = MessageBubble(
      message: message,
      isMe: isMe,
      isFirst: isFirst,
      highlighted: message.eventId == highlightedEventId,
      isPinned: isPinned,
      avatarResolver: avatarResolver,
      htmlBuilder: (html, style) => HtmlMessageText(
        html: html,
        style: style,
        isMe: isMe,
        mentionResolver: mentionResolver,
        mediaResolver: mediaResolver,
      ),
      replyPreview: replyPreview,
      mediaBody: mediaBody,
      onOpenContextMenu:
          isRedacted ? null : (position) => onOpenContextMenu?.call(position),
      onTapSender: onTapSender,
      onReply: isRedacted ? null : onReply,
      onEdit: !isRedacted && isMe ? onEdit : null,
      onDelete: !isRedacted && canRedact ? onDelete : null,
      onReact: isRedacted
          ? null
          : () => showEmojiPickerSheet(context, onToggleReaction),
      onQuickReact: isRedacted ? null : onToggleReaction,
      onPin: canPin ? onPin : null,
      onReplyInThread: isRedacted || inThread ? null : onReplyInThread,
      onForward: isRedacted || onForward == null ? null : onForward,
      reactionBubble: reactionBubble,
      subBubble: subBubble,
      threadIndicator: showThread
          ? ThreadIndicatorChip(
              replyCount: threadReplyCount,
              isMe: isMe,
              unreadCount: threadUnreadCount,
              onTap: () => onOpenThread?.call(),
            )
          : null,
    );

    if (isMobile) {
      return SwipeableMessage(
        onReply: () => onReply?.call(),
        child: LongPressWrapper(
          onLongPress: (rect) => onShowMobileActions?.call(rect),
          child: content,
        ),
      );
    }
    return content;
  }
}

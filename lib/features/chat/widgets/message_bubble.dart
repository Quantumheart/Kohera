import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/message_bubble_content.dart';
import 'package:kohera/features/chat/widgets/message_bubble_hover_bar_slot.dart';
import 'package:kohera/features/chat/widgets/message_bubble_skin.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:provider/provider.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    required this.message,
    required this.isMe,
    required this.isFirst,
    required this.avatarResolver,
    required this.htmlBuilder,
    super.key,
    this.highlighted = false,
    this.isPinned = false,
    this.replyPreview,
    this.mediaBody,
    this.onOpenContextMenu,
    this.onTapSender,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReact,
    this.onQuickReact,
    this.onPin,
    this.onReplyInThread,
    this.onForward,
    this.reactionBubble,
    this.subBubble,
    this.threadIndicator,
  });

  final KoheraMessageDisplay message;
  final bool isMe;

  /// Whether this is the first message in a group from the same sender.
  final bool isFirst;

  /// Whether this message should be visually highlighted (e.g. from search).
  final bool highlighted;

  /// Whether this message is pinned in the room.
  final bool isPinned;

  /// Avatar resolver for sender avatars.
  final AvatarResolver avatarResolver;

  /// Callback for building HTML message widgets (needs SDK Room, provided by
  /// the conversion boundary).
  final HtmlBodyBuilder htmlBuilder;

  /// Pre-built reply preview widget (needs SDK Event, out of scope #6).
  final Widget? replyPreview;

  /// Pre-built media body widget (needs SDK Event, out of scope #7).
  final Widget? mediaBody;

  /// Called when the user triggers the context menu at [position].
  final void Function(Offset position)? onOpenContextMenu;

  /// Called when the user taps the sender avatar.
  final VoidCallback? onTapSender;

  /// Called to initiate a reply to this message.
  final VoidCallback? onReply;

  /// Called to initiate editing this message (own messages only).
  final VoidCallback? onEdit;

  /// Called to delete/redact this message.
  final VoidCallback? onDelete;

  /// Called to open the emoji picker for reacting to this message.
  final VoidCallback? onReact;

  /// Called with a specific emoji for quick-reacting to this message.
  final void Function(String emoji)? onQuickReact;

  /// Called to pin or unpin this message.
  final VoidCallback? onPin;

  /// Called to start a thread reply rooted at this event.
  final VoidCallback? onReplyInThread;

  /// Called to forward this message to another room.
  final VoidCallback? onForward;

  /// Reaction chips overlapping the bottom edge of the bubble (Signal-style).
  final Widget? reactionBubble;

  /// Widget displayed below the bubble (e.g. read receipts).
  final Widget? subBubble;

  /// Optional thread indicator chip (shown below the bubble).
  final Widget? threadIndicator;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final ValueNotifier<bool> _hovering = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _quickReactOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovering.dispose();
    _quickReactOpen.dispose();
    super.dispose();
  }

  void _openContextMenu(Offset position) {
    widget.onOpenContextMenu?.call(position);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = DensityMetrics.of(density);
    final isDesktop = !isTouchDevice;

    Widget bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: EdgeInsets.only(
        top: widget.isFirst
            ? metrics.firstMessageTopPad
            : metrics.messageTopPad,
        bottom: metrics.messageBottomPad,
      ),
      decoration: BoxDecoration(
        color: widget.highlighted
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isMe) _avatarSlot(showAvatar: widget.isFirst, metrics: metrics),
          Flexible(
            child: Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MessageBubbleHoverBarSlot(
                      enabled: isDesktop && widget.isMe,
                      hovering: _hovering,
                      onReact: widget.onReact,
                      onQuickReact: widget.onQuickReact,
                      onReply: widget.onReply,
                      onMore: _openContextMenu,
                      onQuickReactOpenChanged: (open) =>
                          _quickReactOpen.value = open,
                    ),
                    Flexible(
                      child: RepaintBoundary(
                        child: MessageBubbleSkin(
                          isMe: widget.isMe,
                          isFirst: widget.isFirst,
                          metrics: metrics,
                          reactionBubble: widget.reactionBubble,
                          child: MessageBubbleContent(
                            message: widget.message,
                            isMe: widget.isMe,
                            isFirst: widget.isFirst,
                            isPinned: widget.isPinned,
                            metrics: metrics,
                            htmlBuilder: widget.htmlBuilder,
                            replyPreview: widget.replyPreview,
                            mediaBody: widget.mediaBody,
                          ),
                        ),
                      ),
                    ),
                    MessageBubbleHoverBarSlot(
                      enabled: isDesktop && !widget.isMe,
                      hovering: _hovering,
                      onReact: widget.onReact,
                      onQuickReact: widget.onQuickReact,
                      onReply: widget.onReply,
                      onMore: _openContextMenu,
                      onQuickReactOpenChanged: (open) =>
                          _quickReactOpen.value = open,
                    ),
                    if (widget.isMe)
                      _avatarSlot(showAvatar: widget.isFirst, metrics: metrics),
                  ],
                ),
                if (widget.threadIndicator != null) widget.threadIndicator!,
                if (widget.subBubble != null) widget.subBubble!,
              ],
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      bubble = MouseRegion(
        onEnter: (_) => _hovering.value = true,
        // Belt-and-suspenders: onEnter can be missed on Flutter web canvas,
        // so onHover (fires on every mouse-move inside the region) ensures
        // the bar eventually appears even if the enter event was dropped.
        onHover: (_) { if (!_hovering.value) _hovering.value = true; },
        onExit: (_) {
          if (!_quickReactOpen.value) _hovering.value = false;
        },
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton) {
              _openContextMenu(event.position);
            }
          },
          child: bubble,
        ),
      );
    }

    return bubble;
  }

  Widget _avatarSlot({
    required bool showAvatar,
    required DensityMetrics metrics,
  }) {
    if (showAvatar) {
      final diameter = metrics.avatarRadius * 2;
      return Padding(
        padding: EdgeInsets.only(
          left: widget.isMe ? 8 : 0,
          right: widget.isMe ? 0 : 8,
        ),
        child: InkResponse(
          radius: metrics.avatarRadius,
          mouseCursor: SystemMouseCursors.click,
          onTap: widget.onTapSender,
          child: UserAvatar(
            avatarResolver: widget.avatarResolver,
            avatarUrl: widget.message.senderAvatarUrl,
            userId: widget.message.senderId,
            displayname: widget.message.senderName,
            size: diameter,
          ),
        ),
      );
    }
    return SizedBox(width: metrics.avatarRadius * 2 + 8);
  }
}

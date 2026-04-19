import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/hover_action_bar.dart';
import 'package:kohera/features/chat/widgets/inline_reply_preview.dart';
import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/message_bubble_context_menu.dart';
import 'package:kohera/features/chat/widgets/message_bubble_link_preview.dart';
import 'package:kohera/features/chat/widgets/message_bubble_skin.dart';
import 'package:kohera/features/chat/widgets/message_bubble_timestamp.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    required this.event, required this.isMe, required this.isFirst, super.key,
    this.highlighted = false,
    this.isPinned = false,
    this.timeline,
    this.onTapReply,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReact,
    this.onQuickReact,
    this.onPin,
    this.reactionBubble,
    this.subBubble,
  });

  final Event event;
  final bool isMe;

  /// Whether this is the first message in a group from the same sender.
  final bool isFirst;

  /// Whether this message should be visually highlighted (e.g. from search).
  final bool highlighted;

  /// Whether this message is pinned in the room.
  final bool isPinned;

  /// Timeline for resolving reply parent events.
  final Timeline? timeline;

  /// Called when user taps an inline reply preview to scroll to the parent.
  final void Function(Event)? onTapReply;

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

  /// Reaction chips overlapping the bottom edge of the bubble (Signal-style).
  final Widget? reactionBubble;

  /// Widget displayed below the bubble (e.g. read receipts).
  final Widget? subBubble;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovering = false;
  bool _quickReactOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = DensityMetrics.of(density);
    final isDesktop = !isTouchDevice;

    final isRedacted = widget.event.redacted;

    // Resolve edits: use the display event for rendered content.
    final displayEvent = widget.timeline != null
        ? widget.event.getDisplayEvent(widget.timeline!)
        : widget.event;
    final isEdited = !isRedacted &&
        widget.timeline != null &&
        widget.event.hasAggregatedEvents(
            widget.timeline!, RelationshipTypes.edit,);

    final replyEventId = widget.event.content
            .tryGet<Map<String, Object?>>('m.relates_to')
            ?.tryGet<Map<String, Object?>>('m.in_reply_to')
            ?.tryGet<String>('event_id');

    final bodyText = replyEventId != null
        ? stripReplyFallback(displayEvent.body)
        : displayEvent.body;

    final senderName =
        widget.event.senderFromMemoryOrFallback.displayName ??
            widget.event.senderId;

    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyEventId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InlineReplyPreview(
              event: widget.event,
              timeline: widget.timeline,
              isMe: widget.isMe,
              onTap: widget.onTapReply,
            ),
          ),
        if (!widget.isMe && widget.isFirst)
          Padding(
            padding: EdgeInsets.only(bottom: metrics.senderNameBottomPad),
            child: Text(
              senderName,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: metrics.senderNameFontSize,
                color: senderColor(widget.event.senderId, cs),
              ),
            ),
          ),
        MessageBubbleBody(
          event: widget.event,
          displayEvent: displayEvent,
          bodyText: bodyText,
          isMe: widget.isMe,
          metrics: metrics,
        ),
        if (_isTextMessage &&
            context.select<PreferencesService, bool>((p) => p.showLinkPreviews))
          MessageBubbleLinkPreview(bodyText: bodyText, isMe: widget.isMe),
        MessageBubbleTimestamp(
          event: widget.event,
          isMe: widget.isMe,
          isPinned: widget.isPinned,
          isEdited: isEdited,
          metrics: metrics,
        ),
      ],
    );

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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isMe) _avatarSlot(showAvatar: widget.isFirst, padLeft: false, metrics: metrics),
          Flexible(
            child: Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDesktop && _hovering && widget.isMe)
                      _buildHoverBar(cs),
                    Flexible(
                      child: MessageBubbleSkin(
                        isMe: widget.isMe,
                        isFirst: widget.isFirst,
                        metrics: metrics,
                        reactionBubble: widget.reactionBubble,
                        child: bubbleContent,
                      ),
                    ),
                    if (isDesktop && _hovering && !widget.isMe)
                      _buildHoverBar(cs),
                    if (widget.isMe)
                      _avatarSlot(
                          showAvatar: widget.isFirst,
                          padLeft: true,
                          metrics: metrics,),
                  ],
                ),
                if (widget.subBubble != null) widget.subBubble!,
              ],
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      bubble = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) {
          if (!_quickReactOpen) setState(() => _hovering = false);
        },
        child: GestureDetector(
          onSecondaryTapUp: (details) => showMessageContextMenu(
            context,
            event: widget.event,
            isMe: widget.isMe,
            isPinned: widget.isPinned,
            timeline: widget.timeline,
            position: details.globalPosition,
            onReply: widget.onReply,
            onEdit: widget.onEdit,
            onReact: widget.onReact,
            onPin: widget.onPin,
            onDelete: widget.onDelete,
          ),
          child: bubble,
        ),
      );
    }

    return bubble;
  }

  Widget _avatarSlot({
    required bool showAvatar,
    required bool padLeft,
    required DensityMetrics metrics,
  }) {
    if (showAvatar) {
      return Padding(
        padding: EdgeInsets.only(left: padLeft ? 8 : 0, right: padLeft ? 0 : 8),
        child: UserAvatar(
          client: widget.event.room.client,
          avatarUrl: widget.event.senderFromMemoryOrFallback.avatarUrl,
          userId: widget.event.senderId,
          size: metrics.avatarRadius * 2,
        ),
      );
    }
    return SizedBox(width: metrics.avatarRadius * 2 + 8);
  }

  Widget _buildHoverBar(ColorScheme cs) {
    return HoverActionBar(
      cs: cs,
      onReact: widget.onReact,
      onQuickReact: widget.onQuickReact,
      onReply: widget.onReply,
      onMore: (pos) => showMessageContextMenu(
        context,
        event: widget.event,
        isMe: widget.isMe,
        isPinned: widget.isPinned,
        timeline: widget.timeline,
        position: pos,
        onReply: widget.onReply,
        onEdit: widget.onEdit,
        onReact: widget.onReact,
        onPin: widget.onPin,
        onDelete: widget.onDelete,
      ),
      onQuickReactOpenChanged: (open) {
        if (mounted) setState(() => _quickReactOpen = open);
      },
    );
  }

  /// Whether the event is a plain text or notice message (not image/file/etc).
  bool get _isTextMessage {
    final type = widget.event.messageType;
    return !widget.event.redacted &&
        (type == MessageTypes.Text || type == MessageTypes.Notice);
  }
}

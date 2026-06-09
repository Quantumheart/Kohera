import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/message_action_sheet.dart';
import 'package:kohera/features/chat/widgets/message_bubble_context_menu.dart';
import 'package:kohera/features/chat/widgets/message_bubble_hover_bar_slot.dart';
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:kohera/features/chat/widgets/sticker_bubble.dart';
import 'package:matrix/matrix.dart';

class StickerMessageItem extends StatefulWidget {
  const StickerMessageItem({
    required this.event,
    required this.isMe,
    required this.isMobile,
    required this.onToggleReaction,
    this.timeline,
    this.client,
    this.onReply,
    this.onPin,
    this.onForward,
    this.isPinned = false,
    this.highlightedEventId,
    super.key,
  });

  final Event event;
  final bool isMe;
  final bool isMobile;
  final Future<void> Function(Event event, String emoji) onToggleReaction;
  final Timeline? timeline;
  final Client? client;
  final void Function(Event event)? onReply;
  final Future<void> Function(Event event)? onPin;
  final void Function(Event event)? onForward;
  final bool isPinned;
  final String? highlightedEventId;

  @override
  State<StickerMessageItem> createState() => _StickerMessageItemState();
}

class _StickerMessageItemState extends State<StickerMessageItem> {
  final ValueNotifier<bool> _hovering = ValueNotifier(false);
  final ValueNotifier<bool> _quickReactOpen = ValueNotifier(false);

  @override
  void dispose() {
    _hovering.dispose();
    _quickReactOpen.dispose();
    super.dispose();
  }

  void _openContextMenu(Offset position) {
    unawaited(showMessageContextMenu(
      context,
      event: widget.event,
      isMe: widget.isMe,
      isPinned: widget.isPinned,
      timeline: widget.timeline,
      position: position,
      onReply: () => widget.onReply?.call(widget.event),
      onReact: () => showEmojiPickerSheet(
        context,
        (emoji) => widget.onToggleReaction(widget.event, emoji),
      ),
      onPin: widget.onPin != null
          ? () => widget.onPin!.call(widget.event)
          : null,
      onForward: widget.onForward != null
          ? () => widget.onForward!.call(widget.event)
          : null,
    ),);
  }

  void _showMobileActions(Rect bubbleRect) {
    final cs = Theme.of(context).colorScheme;
    showMessageActionSheet(
      context: context,
      event: widget.event,
      isMe: widget.isMe,
      bubbleRect: bubbleRect,
      timeline: widget.timeline,
      onQuickReact: (emoji) => widget.onToggleReaction(widget.event, emoji),
      actions: [
        MessageAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          onTap: () => widget.onReply?.call(widget.event),
        ),
        MessageAction(
          label: 'React',
          icon: Icons.add_reaction_outlined,
          onTap: () => showEmojiPickerSheet(
            context,
            (emoji) => widget.onToggleReaction(widget.event, emoji),
          ),
        ),
        if (widget.onForward != null)
          MessageAction(
            label: 'Forward',
            icon: Icons.forward_rounded,
            onTap: () => widget.onForward!.call(widget.event),
          ),
        if (widget.onPin != null)
          MessageAction(
            label: widget.isPinned ? 'Unpin' : 'Pin',
            icon: widget.isPinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            onTap: () => widget.onPin!.call(widget.event),
          ),
        MessageAction(
          label: 'Copy link',
          icon: Icons.link_rounded,
          onTap: () {
            unawaited(Clipboard.setData(
              ClipboardData(
                text: widget.event.content.tryGet<String>('url') ?? '',
              ),
            ),);
          },
          color: cs.onSurface,
        ),

      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !isTouchDevice;
    final timeline = widget.timeline;
    final client = widget.client;

    final hasReactions = timeline != null &&
        widget.event.hasAggregatedEvents(timeline, RelationshipTypes.reaction);

    Widget sticker = Column(
      crossAxisAlignment:
          widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            MessageBubbleHoverBarSlot(
              enabled: isDesktop && widget.isMe,
              hovering: _hovering,
              onReact: () => showEmojiPickerSheet(
                context,
                (emoji) => widget.onToggleReaction(widget.event, emoji),
              ),
              onQuickReact: (emoji) =>
                  widget.onToggleReaction(widget.event, emoji),
              onReply: () => widget.onReply?.call(widget.event),
              onMore: _openContextMenu,
              onQuickReactOpenChanged: (open) => _quickReactOpen.value = open,
            ),
            StickerBubble(event: widget.event, isMe: widget.isMe),
            MessageBubbleHoverBarSlot(
              enabled: isDesktop && !widget.isMe,
              hovering: _hovering,
              onReact: () => showEmojiPickerSheet(
                context,
                (emoji) => widget.onToggleReaction(widget.event, emoji),
              ),
              onQuickReact: (emoji) =>
                  widget.onToggleReaction(widget.event, emoji),
              onReply: () => widget.onReply?.call(widget.event),
              onMore: _openContextMenu,
              onQuickReactOpenChanged: (open) => _quickReactOpen.value = open,
            ),
          ],
        ),
        if (hasReactions && client != null)
          Padding(
            padding: EdgeInsets.only(
              left: widget.isMe ? 0 : 12,
              right: widget.isMe ? 12 : 0,
              bottom: 4,
            ),
            child: ReactionChips(
              event: widget.event,
              timeline: timeline,
              client: client,
              isMe: widget.isMe,
              onToggle: (emoji) =>
                  widget.onToggleReaction(widget.event, emoji),
            ),
          ),
      ],
    );

    if (isDesktop) {
      sticker = MouseRegion(
        onEnter: (_) => _hovering.value = true,
        onExit: (_) {
          if (!_quickReactOpen.value) _hovering.value = false;
        },
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton) {
              _openContextMenu(event.position);
            }
          },
          child: sticker,
        ),
      );
    } else {
      sticker = LongPressWrapper(
        onLongPress: _showMobileActions,
        child: sticker,
      );
    }

    return sticker;
  }
}

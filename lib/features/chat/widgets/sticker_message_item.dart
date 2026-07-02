import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/message_bubble_hover_bar_slot.dart';

class StickerMessageItem extends StatefulWidget {
  const StickerMessageItem({
    required this.message,
    required this.stickerWidget,
    required this.isMe,
    required this.isMobile,
    required this.onToggleReaction,
    this.reactionWidget,
    this.onReply,
    this.onPin,
    this.onForward,
    this.onOpenContextMenu,
    this.onShowMobileActions,
    this.isPinned = false,
    this.highlightedEventId,
    super.key,
  });

  final KoheraMessageDisplay message;
  final Widget stickerWidget;
  final bool isMe;
  final bool isMobile;
  final Future<void> Function(String eventId, String emoji) onToggleReaction;
  final Widget? reactionWidget;
  final void Function(String eventId)? onReply;
  final Future<void> Function(String eventId)? onPin;
  final void Function(String eventId)? onForward;
  final void Function(Offset position)? onOpenContextMenu;
  final void Function(Rect bubbleRect)? onShowMobileActions;
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
    widget.onOpenContextMenu?.call(position);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !isTouchDevice;

    final eventId = widget.message.eventId;

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
                (emoji) => widget.onToggleReaction(eventId, emoji),
              ),
              onQuickReact: (emoji) =>
                  widget.onToggleReaction(eventId, emoji),
              onReply: () => widget.onReply?.call(eventId),
              onMore: _openContextMenu,
              onQuickReactOpenChanged: (open) => _quickReactOpen.value = open,
            ),
            widget.stickerWidget,
            MessageBubbleHoverBarSlot(
              enabled: isDesktop && !widget.isMe,
              hovering: _hovering,
              onReact: () => showEmojiPickerSheet(
                context,
                (emoji) => widget.onToggleReaction(eventId, emoji),
              ),
              onQuickReact: (emoji) =>
                  widget.onToggleReaction(eventId, emoji),
              onReply: () => widget.onReply?.call(eventId),
              onMore: _openContextMenu,
              onQuickReactOpenChanged: (open) => _quickReactOpen.value = open,
            ),
          ],
        ),
        if (widget.reactionWidget != null)
          Padding(
            padding: EdgeInsets.only(
              left: widget.isMe ? 0 : 12,
              right: widget.isMe ? 12 : 0,
              bottom: 4,
            ),
            child: widget.reactionWidget,
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
        onLongPress: (rect) => widget.onShowMobileActions?.call(rect),
        child: sticker,
      );
    }

    return sticker;
  }
}

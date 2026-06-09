import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show BottomActionBarConfig, CategoryViewConfig, Config, DefaultEmojiTextStyle,
         EmojiPicker, EmojiViewConfig, SearchViewConfig,
         SkinToneConfig;
import 'package:flutter/material.dart';

// ── Hover action bar ────────────────────────────────────────

class HoverActionBar extends StatefulWidget {
  const HoverActionBar({
    required this.cs, required this.onMore, super.key,
    this.onReact,
    this.onQuickReact,
    this.onReply,
    this.onQuickReactOpenChanged,
  });

  final ColorScheme cs;
  final VoidCallback? onReact;
  final void Function(String emoji)? onQuickReact;
  final VoidCallback? onReply;
  final void Function(Offset position) onMore;

  /// Notifies the parent when the quick-react overlay opens/closes.
  final ValueChanged<bool>? onQuickReactOpenChanged;

  @override
  State<HoverActionBar> createState() => _HoverActionBarState();
}

class _HoverActionBarState extends State<HoverActionBar> {
  OverlayEntry? _overlayEntry;

  bool _disposing = false;

  @override
  void dispose() {
    _disposing = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (!_disposing) {
      widget.onQuickReactOpenChanged?.call(false);
    }
  }

  void _showQuickReactPopup() {
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    widget.onQuickReactOpenChanged?.call(true);

    final anchorRect = box.localToGlobal(Offset.zero) & box.size;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _QuickReactOverlay(
        anchorRect: anchorRect,
        cs: widget.cs,
        hasMore: widget.onReact != null,
        onEmojiSelected: (emoji) {
          _removeOverlay();
          widget.onQuickReact?.call(emoji);
        },
        onDismiss: _removeOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final hasReact = widget.onReact != null || widget.onQuickReact != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        color: widget.cs.surfaceContainerHighest,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasReact)
              _ActionIcon(
                icon: Icons.add_reaction_outlined,
                onTap: _showQuickReactPopup,
                cs: widget.cs,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            if (widget.onReply != null)
              _ActionIcon(
                icon: Icons.reply_rounded,
                onTap: widget.onReply!,
                cs: widget.cs,
              ),
            _ActionIcon(
              icon: Icons.more_horiz_rounded,
              onTap: () {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || !box.hasSize) return;
                final pos = box.localToGlobal(
                  Offset(box.size.width, box.size.height / 2),
                );
                widget.onMore(pos);
              },
              cs: widget.cs,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action icon ─────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.onTap,
    required this.cs,
    this.borderRadius,
  });

  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: borderRadius ?? BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }
}

// ── Quick-react overlay ─────────────────────────────────────

class _QuickReactOverlay extends StatefulWidget {
  const _QuickReactOverlay({
    required this.anchorRect,
    required this.cs,
    required this.hasMore,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  final Rect anchorRect;
  final ColorScheme cs;

  /// Whether to show the "..." button (only when a full emoji picker is available).
  final bool hasMore;
  final void Function(String emoji) onEmojiSelected;
  final VoidCallback onDismiss;

  @override
  State<_QuickReactOverlay> createState() => _QuickReactOverlayState();
}

class _QuickReactOverlayState extends State<_QuickReactOverlay> {
  bool _showPicker = false;

  static const _quickEmojis = [
    '\u{2764}\u{FE0F}', // ❤️
    '\u{1F44D}', // 👍
    '\u{1F44E}', // 👎
    '\u{1F602}', // 😂
    '\u{1F622}', // 😢
    '\u{1F62E}', // 😮
  ];

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    const gap = 4.0;
    const margin = 8.0;

    return Stack(
      children: [
        // Dismiss scrim
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        // Clamped overlay — centered on anchor, never clipped by screen edges
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _OverlayPositionDelegate(
              anchorRect: widget.anchorRect,
              gap: gap,
              margin: margin,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Full emoji picker (above the quick-react bar)
                if (_showPicker)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: cs.surfaceContainer,
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: 350,
                        height: 400,
                        child: EmojiPicker(
                          onEmojiSelected: (category, emoji) {
                            widget.onEmojiSelected(emoji.emoji);
                          },
                          config: Config(
                            emojiTextStyle: DefaultEmojiTextStyle,
                            emojiViewConfig: EmojiViewConfig(
                              columns: 8,
                              backgroundColor: cs.surfaceContainer,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backgroundColor: cs.surfaceContainer,
                              indicatorColor: cs.primary,
                              iconColorSelected: cs.primary,
                              iconColor: cs.onSurfaceVariant,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor:
                                  cs.surfaceContainerHighest,
                              indicatorColor: cs.primary,
                            ),
                            bottomActionBarConfig: BottomActionBarConfig(
                              backgroundColor: cs.surfaceContainer,
                              buttonColor: cs.primary,
                            ),
                            searchViewConfig: SearchViewConfig(
                              backgroundColor: cs.surfaceContainer,
                              buttonIconColor: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Quick-react bar
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(20),
                  color: cs.surfaceContainerHighest,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final emoji in _quickEmojis)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => widget.onEmojiSelected(emoji),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                emoji,
                                style: DefaultEmojiTextStyle.copyWith(
                                    fontSize: 22,),
                              ),
                            ),
                          ),
                        if (widget.hasMore)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () =>
                                setState(() => _showPicker = !_showPicker),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 22,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Overlay position delegate ───────────────────────────────

class _OverlayPositionDelegate extends SingleChildLayoutDelegate {
  const _OverlayPositionDelegate({
    required this.anchorRect,
    required this.gap,
    required this.margin,
  });

  final Rect anchorRect;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Center horizontally on the anchor, clamped within the margin.
    var left = anchorRect.center.dx - childSize.width / 2;
    left = left.clamp(margin, size.width - childSize.width - margin);

    // Place just above the anchor, clamped so it never goes off the top.
    var top = anchorRect.top - childSize.height - gap;
    top = top.clamp(margin, size.height - childSize.height - margin);

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_OverlayPositionDelegate old) =>
      old.anchorRect != anchorRect ||
      old.gap != gap ||
      old.margin != margin;
}

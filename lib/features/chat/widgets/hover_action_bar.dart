import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/features/chat/widgets/openmoji_picker.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';
import 'package:provider/provider.dart';

/// Emoji offered in the quick-react bar, in display order.
const kQuickReactEmojis = [
  '\u{2764}\u{FE0F}', // ❤️
  '\u{1F44D}', // 👍
  '\u{1F44E}', // 👎
  '\u{1F602}', // 😂
  '\u{1F622}', // 😢
  '\u{1F62E}', // 😮
];

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
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached && widget.onQuickReact != null) {
      _precached = true;
      unawaited(precacheOpenMoji(context, kQuickReactEmojis));
    }
  }

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

    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorTopCenter = box.localToGlobal(
      Offset(box.size.width / 2, 0),
      ancestor: overlayBox,
    );

    widget.onQuickReactOpenChanged?.call(true);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _QuickReactOverlay(
        anchorTopCenter: anchorTopCenter,
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
      mouseCursor: SystemMouseCursors.click,
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
    required this.anchorTopCenter,
    required this.cs,
    required this.hasMore,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  /// Top-center of the action bar, in the overlay's coordinate space.
  final Offset anchorTopCenter;
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

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final tone = context.watch<PreferencesService>().skinTone;
    const gap = 4.0;
    const margin = 8.0;

    final pickerWidth =
        (MediaQuery.sizeOf(context).width - margin * 2).clamp(0.0, 350.0);

    return Stack(
      children: [
        // Dismiss scrim
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _QuickReactLayoutDelegate(
              anchorTopCenter: widget.anchorTopCenter,
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
                        width: pickerWidth,
                        height: 400,
                        child: OpenMojiPicker(
                          skinTone: context.watch<PreferencesService>().skinTone,
                          onSkinToneChanged:
                              context.read<PreferencesService>().setSkinTone,
                          onSelected: widget.onEmojiSelected,
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
                        for (final emoji in kQuickReactEmojis)
                          () {
                            final toned = applySkinTone(emoji, tone);
                            return InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => widget.onEmojiSelected(toned),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text.rich(
                                  TextSpan(
                                    children: buildEmojiSpans(
                                      toned,
                                      emojiTextStyle.copyWith(fontSize: 22),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }(),
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

// ── Quick-react layout delegate ─────────────────────────────
//
// Positions the popup so its bottom-center sits above [anchorTopCenter], then
// clamps it inside the viewport (minus [margin]) so it never overflows a screen
// edge on narrow layouts.
class _QuickReactLayoutDelegate extends SingleChildLayoutDelegate {
  _QuickReactLayoutDelegate({
    required this.anchorTopCenter,
    required this.gap,
    required this.margin,
  });

  final Offset anchorTopCenter;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        (constraints.maxWidth - margin * 2).clamp(0.0, double.infinity),
        (constraints.maxHeight - margin * 2).clamp(0.0, double.infinity),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final dx = (anchorTopCenter.dx - childSize.width / 2)
        .clamp(margin, size.width - margin - childSize.width);
    final dy = (anchorTopCenter.dy - gap - childSize.height)
        .clamp(margin, size.height - margin - childSize.height);
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_QuickReactLayoutDelegate oldDelegate) =>
      anchorTopCenter != oldDelegate.anchorTopCenter ||
      gap != oldDelegate.gap ||
      margin != oldDelegate.margin;
}

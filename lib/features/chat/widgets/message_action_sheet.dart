import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/services/linkable_span_builder.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/message_bubble.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:provider/provider.dart';

// ── Data class ──────────────────────────────────────────

class MessageAction {
  const MessageAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
}

// ── Public entry point ──────────────────────────────────

void showMessageActionSheet({
  required BuildContext context,
  required KoheraMessageDisplay message,
  required bool isMe,
  required Rect bubbleRect,
  required List<MessageAction> actions,
  required AvatarResolver avatarResolver,
  required MentionDisplayNameResolver mentionResolver,
  required MediaResolver mediaResolver,
  void Function(String emoji)? onQuickReact,
}) {
  unawaited(
    Navigator.of(context).push(
      _MessageActionSheetRoute(
        message: message,
        isMe: isMe,
        bubbleRect: bubbleRect,
        actions: actions,
        avatarResolver: avatarResolver,
        mentionResolver: mentionResolver,
        mediaResolver: mediaResolver,
        capturedTheme: Theme.of(context),
        onQuickReact: onQuickReact,
      ),
    ),
  );
}

// ── Route ───────────────────────────────────────────────

class _MessageActionSheetRoute extends PopupRoute<void> {
  _MessageActionSheetRoute({
    required this.message,
    required this.isMe,
    required this.bubbleRect,
    required this.actions,
    required this.avatarResolver,
    required this.mentionResolver,
    required this.mediaResolver,
    required this.capturedTheme,
    this.onQuickReact,
  });

  final KoheraMessageDisplay message;
  final bool isMe;
  final Rect bubbleRect;
  final List<MessageAction> actions;
  final AvatarResolver avatarResolver;
  final MentionDisplayNameResolver mentionResolver;
  final MediaResolver mediaResolver;
  final ThemeData capturedTheme;
  final void Function(String emoji)? onQuickReact;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _MessageActionSheet(
      message: message,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      avatarResolver: avatarResolver,
      mentionResolver: mentionResolver,
      mediaResolver: mediaResolver,
      animation: animation,
      capturedTheme: capturedTheme,
      onQuickReact: onQuickReact,
    );
  }
}

// ── Overlay layout ──────────────────────────────────────

class _MessageActionSheet extends StatefulWidget {
  const _MessageActionSheet({
    required this.message,
    required this.isMe,
    required this.bubbleRect,
    required this.actions,
    required this.avatarResolver,
    required this.mentionResolver,
    required this.mediaResolver,
    required this.animation,
    required this.capturedTheme,
    this.onQuickReact,
  });

  final KoheraMessageDisplay message;
  final bool isMe;
  final Rect bubbleRect;
  final List<MessageAction> actions;
  final AvatarResolver avatarResolver;
  final MentionDisplayNameResolver mentionResolver;
  final MediaResolver mediaResolver;
  final Animation<double> animation;
  final ThemeData capturedTheme;
  final void Function(String emoji)? onQuickReact;

  @override
  State<_MessageActionSheet> createState() => _MessageActionSheetState();
}

class _MessageActionSheetState extends State<_MessageActionSheet> {
  static const _actionListWidth = 240.0;
  static const _actionRowHeight = 48.0;
  static const _quickReactHeight = 48.0;
  static const _gap = 8.0;

  late final CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    final screenWidth = mq.size.width;
    final safeTop = mq.padding.top + 8;
    final safeBottom = mq.padding.bottom + 8;

    final hasQuickReact = widget.onQuickReact != null;
    final actionListHeight = widget.actions.length * _actionRowHeight;
    final quickReactSpace = hasQuickReact ? _quickReactHeight + _gap : 0.0;

    final totalHeight =
        widget.bubbleRect.height + _gap + quickReactSpace + actionListHeight;

    var bubbleTop = widget.bubbleRect.top;
    final bottomEdge = bubbleTop + totalHeight;
    if (bottomEdge > screenHeight - safeBottom) {
      bubbleTop = screenHeight - safeBottom - totalHeight;
    }
    if (bubbleTop < safeTop) {
      bubbleTop = safeTop;
    }

    final quickReactTop = bubbleTop + widget.bubbleRect.height + _gap;
    final actionListTop = quickReactTop + quickReactSpace;

    double actionListLeft;
    if (widget.isMe) {
      actionListLeft = widget.bubbleRect.right - _actionListWidth;
    } else {
      actionListLeft = widget.bubbleRect.left;
    }
    actionListLeft =
        clampDouble(actionListLeft, 8, screenWidth - _actionListWidth - 8);

    return Stack(
      children: [
        Positioned(
          top: bubbleTop,
          left: widget.bubbleRect.left,
          width: widget.bubbleRect.width,
          child: FadeTransition(
            opacity: _curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1).animate(_curved),
              child: IgnorePointer(
                child: AbsorbPointer(
                  child: Theme(
                    data: widget.capturedTheme,
                    child: Material(
                      type: MaterialType.transparency,
                      child: MessageBubble(
                        message: widget.message,
                        isMe: widget.isMe,
                        isFirst: true,
                        avatarResolver: widget.avatarResolver,
                        htmlBuilder: (html, style) => HtmlMessageText(
                          html: html,
                          style: style,
                          isMe: widget.isMe,
                          mentionResolver: widget.mentionResolver,
                          mediaResolver: widget.mediaResolver,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasQuickReact)
          Positioned(
            top: quickReactTop,
            left: actionListLeft,
            width: _actionListWidth,
            child: FadeTransition(
              opacity: _curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(_curved),
                child: _QuickReactBar(onQuickReact: widget.onQuickReact!),
              ),
            ),
          ),
        Positioned(
          top: actionListTop,
          left: actionListLeft,
          width: _actionListWidth,
          child: FadeTransition(
            opacity: _curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(_curved),
              child: _ActionList(actions: widget.actions),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Action list widget ──────────────────────────────────

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions});

  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            _ActionRow(action: actions[i]),
          ],
        ],
      ),
    );
  }
}

// ── Quick-reaction bar ──────────────────────────────────

class _QuickReactBar extends StatelessWidget {
  const _QuickReactBar({required this.onQuickReact});

  final void Function(String emoji) onQuickReact;

  static const _quickEmojis = [
    '\u{1F44D}',
    '\u{2764}\u{FE0F}',
    '\u{1F602}',
    '\u{1F62E}',
    '\u{1F622}',
    '\u{1F64F}',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = context.watch<PreferencesService>().skinTone;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _quickEmojis.map((emoji) {
            final toned = applySkinTone(emoji, tone);
            return Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.of(context).pop();
                  onQuickReact(toned);
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text.rich(
                    TextSpan(
                      children: buildEmojiSpans(
                        toned,
                        emojiTextStyle.copyWith(fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final MessageAction action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        action.onTap();
      },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  action.label,
                  style: tt.bodyMedium?.copyWith(
                    color: action.color ?? cs.onSurface,
                  ),
                ),
              ),
              Icon(
                action.icon,
                size: 20,
                color: action.color ?? cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

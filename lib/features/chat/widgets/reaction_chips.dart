import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

// ── ReactionChips ────────────────────────────────────────────

/// Displays aggregated emoji reaction chips below a message bubble.
///
/// Tapping a chip toggles the reaction. Long-pressing opens a sheet listing
/// who reacted. Each chip claims the enclosing [LongPressWrapper] on
/// pointer-down so only one action fires — the chip's own long-press wins
/// and the message action sheet is not shown simultaneously.
class ReactionChips extends StatefulWidget {
  const ReactionChips({
    required this.reactions,
    required this.isMe,
    required this.avatarResolver,
    super.key,
    this.onToggle,
  });

  final KoheraReactionList reactions;
  final bool isMe;
  final AvatarResolver avatarResolver;
  final void Function(String emoji)? onToggle;

  @override
  State<ReactionChips> createState() => _ReactionChipsState();
}

class _ReactionChipsState extends State<ReactionChips> {
  final _pendingToggles = <String>{};
  final _debounceTimers = <String, Timer>{};

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _handleToggle(String emoji) {
    if (_pendingToggles.contains(emoji)) return;
    _pendingToggles.add(emoji);
    widget.onToggle?.call(emoji);
    _debounceTimers[emoji]?.cancel();
    _debounceTimers[emoji] = Timer(const Duration(milliseconds: 600), () {
      _pendingToggles.remove(emoji);
      _debounceTimers.remove(emoji);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reactions.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Wrap(
      alignment: widget.isMe ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: widget.reactions.reactions.map((reaction) {
        final emoji = reaction.key;
        final isMine = reaction.reactedByMe;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => LongPressWrapper.claimOf(context),
          child: GestureDetector(
            onTap: () => _handleToggle(emoji),
            onLongPress: () => showReactorsSheet(
              context,
              reaction: reaction,
              avatarResolver: widget.avatarResolver,
              onToggle: widget.onToggle,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMine
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isMine
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outlineVariant.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: buildEmojiSpans(
                        emoji,
                        emojiTextStyle.copyWith(fontSize: 14),
                      ),
                    ),
                  ),
                  if (reaction.count > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${reaction.count}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isMine ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Reactors bottom sheet ────────────────────────────────────

/// Shows a modal bottom sheet listing all users who reacted with [emoji].
/// If [onToggle] is provided, a button lets the current user add or remove
/// their own reaction directly from the sheet.
void showReactorsSheet(
  BuildContext context, {
  required KoheraReaction reaction,
  required AvatarResolver avatarResolver,
  void Function(String emoji)? onToggle,
}) {
  unawaited(showModalBottomSheet(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    ...buildEmojiSpans(
                      reaction.key,
                      Theme.of(ctx).textTheme.titleMedium,
                    ),
                    TextSpan(
                      text: ' ${reaction.count}',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reaction.reactors.length,
                itemBuilder: (ctx, i) {
                  final reactor = reaction.reactors[i];
                  final name = reactor.displayName ?? reactor.senderId;
                  return ListTile(
                    leading: UserAvatar(
                      avatarResolver: avatarResolver,
                      avatarUrl: reactor.avatarUrl,
                      userId: reactor.senderId,
                      displayname: name,
                      size: 36,
                    ),
                    title: Text(name),
                    subtitle:
                        name != reactor.senderId ? Text(reactor.senderId) : null,
                  );
                },
              ),
            ),
            if (onToggle != null) ...[
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onToggle(reaction.key);
                    },
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: reaction.reactedByMe
                                ? 'Remove your '
                                : 'React with ',
                          ),
                          ...buildEmojiSpans(reaction.key, null),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  ),);
}

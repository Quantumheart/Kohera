import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show DefaultEmojiTextStyle;
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';

// ── ReactionChips ────────────────────────────────────────────

/// Displays aggregated emoji reaction chips below a message bubble.
///
/// Tapping a chip toggles the reaction. Long-pressing opens a sheet listing
/// who reacted. Each chip claims the enclosing [LongPressWrapper] on
/// pointer-down so only one action fires — the chip's own long-press wins
/// and the message action sheet is not shown simultaneously.
class ReactionChips extends StatefulWidget {
  const ReactionChips({
    required this.event,
    required this.timeline,
    required this.client,
    required this.isMe,
    super.key,
    this.onToggle,
  });

  final Event event;
  final Timeline timeline;
  final Client client;
  final bool isMe;
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
    final reactionEvents =
        widget.event.aggregatedEvents(widget.timeline, RelationshipTypes.reaction);
    if (reactionEvents.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<Event>>{};
    for (final re in reactionEvents) {
      final key = re.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        (grouped[key] ??= []).add(re);
      }
    }
    if (grouped.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final myId = widget.client.userID;

    return Wrap(
      alignment: widget.isMe ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: grouped.entries.map((entry) {
        final emoji = entry.key;
        final events = entry.value;
        final isMine = events.any((e) => e.senderId == myId);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => LongPressWrapper.claimOf(context),
          child: GestureDetector(
            onTap: () => _handleToggle(emoji),
            onLongPress: () => showReactorsSheet(
              context,
              emoji: emoji,
              reactionEvents: events,
              room: widget.event.room,
              client: widget.client,
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
                        DefaultEmojiTextStyle.copyWith(fontSize: 14),
                      ),
                    ),
                  ),
                  if (events.length > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${events.length}',
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
  required String emoji,
  required List<Event> reactionEvents,
  required Room room,
  required Client client,
  void Function(String emoji)? onToggle,
}) {
  unawaited(showModalBottomSheet(
    context: context,
    builder: (ctx) {
      final myId = client.userID;
      final isMine = reactionEvents.any((e) => e.senderId == myId);

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
                      emoji,
                      Theme.of(ctx).textTheme.titleMedium,
                    ),
                    TextSpan(
                      text: ' ${reactionEvents.length}',
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
                itemCount: reactionEvents.length,
                itemBuilder: (ctx, i) {
                  final re = reactionEvents[i];
                  final user =
                      room.unsafeGetUserFromMemoryOrFallback(re.senderId);
                  final name = user.displayName ?? re.senderId;
                  return ListTile(
                    leading: UserAvatar(
                      client: room.client,
                      avatarUrl: user.avatarUrl,
                      userId: re.senderId,
                      size: 36,
                    ),
                    title: Text(name),
                    subtitle: name != re.senderId ? Text(re.senderId) : null,
                  );
                },
              ),
            ),
            if (onToggle != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onToggle(emoji);
                    },
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: isMine ? 'Remove your ' : 'React with '),
                          ...buildEmojiSpans(emoji, null),
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

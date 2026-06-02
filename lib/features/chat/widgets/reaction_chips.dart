import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show DefaultEmojiTextStyle;
import 'package:flutter/material.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';

// ── ReactionChips ────────────────────────────────────────────

/// Displays aggregated emoji reaction chips below a message bubble.
///
/// Each chip shows the emoji and its count. Chips where the current user
/// has reacted are highlighted. Tapping a chip opens a sheet listing who
/// reacted and allows toggling the current user's reaction.
class ReactionChips extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final reactionEvents =
        event.aggregatedEvents(timeline, RelationshipTypes.reaction);
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
    final myId = client.userID;

    return Wrap(
      alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: grouped.entries.map((entry) {
        final emoji = entry.key;
        final events = entry.value;
        final isMine = events.any((e) => e.senderId == myId);

        return GestureDetector(
          onTap: () => showReactorsSheet(
            context,
            emoji: emoji,
            reactionEvents: events,
            room: event.room,
            client: client,
            onToggle: onToggle,
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
                Text(
                  emoji,
                  style: DefaultEmojiTextStyle.copyWith(fontSize: 14),
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
        );
      }).toList(),
    );
  }
}

// ── Reactors bottom sheet ────────────────────────────────────

/// Shows a modal bottom sheet listing all users who reacted with [emoji],
/// with a button to add or remove the current user's own reaction.
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
              child: Text(
                '$emoji ${reactionEvents.length}',
                style: Theme.of(ctx).textTheme.titleMedium,
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
                    child: Text(isMine ? 'Remove your $emoji' : 'React with $emoji'),
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

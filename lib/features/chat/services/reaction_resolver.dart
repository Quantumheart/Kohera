import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:matrix/matrix.dart';

// ── ReactionResolver ─────────────────────────────────────────

/// Converts Matrix SDK `Event` + `Timeline` reaction aggregation data
/// into a Kohera-owned [KoheraReactionList] at the conversion boundary.
///
/// Widgets below the boundary depend only on [KoheraReactionList] and
/// never touch `Event`, `Timeline`, or `Client`.
class ReactionResolver {
  const ReactionResolver();

  /// Resolves all reactions for [event] from [timeline] into a
  /// [KoheraReactionList].
  ///
  /// [myUserId] is the current user's Matrix ID — used to compute
  /// [KoheraReaction.reactedByMe] for each emoji group.
  KoheraReactionList resolve(
    Event event,
    Timeline timeline, {
    required String myUserId,
  }) {
    final reactionEvents =
        event.aggregatedEvents(timeline, RelationshipTypes.reaction);
    if (reactionEvents.isEmpty) return const KoheraReactionList([]);

    // Group reaction events by emoji key.
    final grouped = <String, List<Event>>{};
    for (final re in reactionEvents) {
      final key = re.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        (grouped[key] ??= []).add(re);
      }
    }
    if (grouped.isEmpty) return const KoheraReactionList([]);

    // Map each group to a KoheraReaction with pre-computed reactor info.
    final room = event.room;
    final reactions = <KoheraReaction>[];
    for (final entry in grouped.entries) {
      final emoji = entry.key;
      final events = entry.value;

      final reactors = events.map((re) {
        final user = room.unsafeGetUserFromMemoryOrFallback(re.senderId);
        return KoheraReactor(
          senderId: re.senderId,
          displayName: user.displayName,
          avatarUrl: user.avatarUrl?.toString(),
        );
      }).toList();

      reactions.add(KoheraReaction(
        key: emoji,
        count: reactors.length,
        reactedByMe: reactors.any((r) => r.senderId == myUserId),
        reactors: reactors,
      ),);
    }

    return KoheraReactionList(reactions);
  }

  /// Returns `true` if [event] has any reaction events in [timeline].
  bool hasReactions(Event event, Timeline timeline) =>
      event.hasAggregatedEvents(timeline, RelationshipTypes.reaction);
}

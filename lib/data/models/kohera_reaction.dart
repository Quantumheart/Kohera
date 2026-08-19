import 'package:flutter/foundation.dart';

// ── KoheraReactor ────────────────────────────────────────────

/// One user who reacted with a specific emoji.
///
/// Pre-computed at the conversion boundary from
/// `Room.unsafeGetUserFromMemoryOrFallback(senderId)` so that
/// [ReactionChips] and the reactors bottom sheet can render
/// without touching `package:matrix/matrix.dart`.
@immutable
class KoheraReactor {
  const KoheraReactor({
    required this.senderId,
    this.displayName,
    this.avatarUrl,
  });

  /// The Matrix user ID (e.g. `@alice:example.com`).
  final String senderId;

  /// Display name from the room member, or `null` if unavailable.
  final String? displayName;

  /// The `mxc://` avatar URI as a string, or `null` if the user
  /// has no avatar.
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraReactor && senderId == other.senderId;

  @override
  int get hashCode => senderId.hashCode;

  KoheraReactor copyWith({
    String? senderId,
    String? displayName,
    String? avatarUrl,
  }) =>
      KoheraReactor(
        senderId: senderId ?? this.senderId,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  @override
  String toString() =>
      'KoheraReactor(senderId: $senderId, displayName: $displayName, '
      'avatarUrl: $avatarUrl)';
}

// ── KoheraReaction ───────────────────────────────────────────

/// A single emoji reaction group: the emoji key, the reactor count,
/// whether the current user reacted, and the list of individual reactors
/// (used by the reactors bottom sheet).
@immutable
class KoheraReaction {
  const KoheraReaction({
    required this.key,
    required this.count,
    required this.reactedByMe,
    required this.reactors,
  });

  /// The emoji string (e.g. '👍') or a custom emoji shortcode
  /// (e.g. ':custom:').
  final String key;

  /// Number of users who reacted with this emoji.
  final int count;

  /// Whether the current user reacted with this emoji.
  final bool reactedByMe;

  /// Individual reactor info for the bottom sheet.
  final List<KoheraReactor> reactors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraReaction && key == other.key;

  @override
  int get hashCode => key.hashCode;

  KoheraReaction copyWith({
    String? key,
    int? count,
    bool? reactedByMe,
    List<KoheraReactor>? reactors,
  }) =>
      KoheraReaction(
        key: key ?? this.key,
        count: count ?? this.count,
        reactedByMe: reactedByMe ?? this.reactedByMe,
        reactors: reactors ?? this.reactors,
      );

  @override
  String toString() =>
      'KoheraReaction(key: $key, count: $count, reactedByMe: $reactedByMe, '
      'reactors: $reactors)';
}

// ── KoheraReactionList ───────────────────────────────────────

/// A pre-computed list of [KoheraReaction] entries for a single message.
///
/// Created by [ReactionResolver] at the conversion boundary from
/// `Event.aggregatedEvents(timeline, RelationshipTypes.reaction)`.
@immutable
class KoheraReactionList {
  const KoheraReactionList(this.reactions);

  /// The reaction entries, one per emoji.
  final List<KoheraReaction> reactions;

  bool get isEmpty => reactions.isEmpty;
  bool get isNotEmpty => reactions.isNotEmpty;

  @override
  String toString() => 'KoheraReactionList(${reactions.length} reactions)';
}

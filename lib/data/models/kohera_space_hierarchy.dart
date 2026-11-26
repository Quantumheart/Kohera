import 'package:flutter/foundation.dart';

/// An `m.space.child` state entry attached to a hierarchy chunk. SDK-free.
@immutable
class KoheraSpaceChildState {
  const KoheraSpaceChildState({
    required this.type,
    this.stateKey,
    this.isSuggested = false,
    this.order,
    this.via = const [],
  });

  /// Event type, e.g. `m.space.child`.
  final String type;

  /// The child room ID (state key of the event).
  final String? stateKey;

  final bool isSuggested;

  /// Ordering hint from the `order` content key, if present.
  final String? order;

  /// Servers to join through, from the `via` content key.
  final List<String> via;
}

/// A room or space within a space hierarchy response. SDK-free.
@immutable
class KoheraSpaceHierarchyChunk {
  const KoheraSpaceHierarchyChunk({
    required this.roomId,
    required this.memberCount,
    required this.worldReadable,
    required this.guestCanJoin,
    this.name,
    this.topic,
    this.canonicalAlias,
    this.avatarUrl,
    this.roomType,
    this.childrenState = const [],
  });

  final String roomId;
  final String? name;
  final String? topic;
  final String? canonicalAlias;
  final Uri? avatarUrl;
  final int memberCount;
  final bool worldReadable;
  final bool guestCanJoin;

  /// The `m.room.create` type, e.g. `m.space`. Null for plain rooms.
  final String? roomType;

  /// `m.space.child` state of this room when it is the requested space.
  final List<KoheraSpaceChildState> childrenState;
}

/// The rooms of a space hierarchy response. SDK-free.
@immutable
class KoheraSpaceHierarchy {
  const KoheraSpaceHierarchy({required this.rooms});

  final List<KoheraSpaceHierarchyChunk> rooms;
}

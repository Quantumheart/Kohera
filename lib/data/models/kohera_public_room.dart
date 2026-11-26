import 'package:flutter/foundation.dart';

/// Filter for the public room directory. SDK-free.
@immutable
class KoheraPublicRoomFilter {
  const KoheraPublicRoomFilter({this.roomTypes, this.genericSearchTerm});

  /// Room types to include (e.g. `['m.space']`). Null means all types.
  final List<String>? roomTypes;

  /// Free-text search across name, topic, and alias.
  final String? genericSearchTerm;
}

/// A public room or space from the homeserver directory. SDK-free.
@immutable
class KoheraPublicRoom {
  const KoheraPublicRoom({
    required this.roomId,
    required this.memberCount,
    required this.worldReadable,
    required this.guestCanJoin,
    this.name,
    this.topic,
    this.canonicalAlias,
    this.avatarUrl,
    this.roomType,
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
}

/// One page of directory results. SDK-free.
@immutable
class KoheraPublicRoomsPage {
  const KoheraPublicRoomsPage({
    required this.items,
    this.nextBatch,
    this.totalRoomCountEstimate,
  });

  final List<KoheraPublicRoom> items;
  final String? nextBatch;
  final int? totalRoomCountEstimate;
}

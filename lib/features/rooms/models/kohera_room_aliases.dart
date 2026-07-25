import 'package:flutter/foundation.dart';

/// Kohera-owned snapshot of a room's alias state.
///
/// Carries no `package:matrix/matrix.dart` dependency. The conversion boundary
/// ([RoomAliasesController]) builds this from the SDK `Room` and the local
/// aliases API, and widgets below the boundary consume it plus callbacks.
@immutable
class KoheraRoomAliases {
  const KoheraRoomAliases({
    required this.roomId,
    required this.aliases,
    required this.canonicalAlias,
    required this.canEdit,
    required this.homeserverDomain,
  });

  /// The Matrix room ID (e.g. `!abc:example.com`).
  final String roomId;

  /// All local aliases of the room (e.g. `#room:example.com`), unsorted from
  /// the server. The canonical alias, if set, is also present here.
  final List<String> aliases;

  /// The canonical alias (`m.room.canonical_alias` `alias` field), or `null`
  /// / empty string when unset.
  final String? canonicalAlias;

  /// Whether the local user can create aliases and change the canonical alias
  /// (sufficient power level for `m.room.canonical_alias`).
  final bool canEdit;

  /// The local user's homeserver domain (e.g. `example.com`), used to build
  /// new local aliases as `#<localpart>:<domain>`.
  final String? homeserverDomain;

  /// Aliases other than the [canonicalAlias].
  List<String> get nonCanonical => canonicalAlias == null || canonicalAlias!.isEmpty
      ? List.unmodifiable(aliases)
      : aliases.where((a) => a != canonicalAlias).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraRoomAliases &&
      roomId == other.roomId &&
      canonicalAlias == other.canonicalAlias &&
      canEdit == other.canEdit &&
      homeserverDomain == other.homeserverDomain &&
      _listEq(aliases, other.aliases);

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        roomId,
        Object.hashAll(aliases),
        canonicalAlias,
        canEdit,
        homeserverDomain,
      );

  @override
  String toString() =>
      'KoheraRoomAliases(roomId: $roomId, canonicalAlias: $canonicalAlias, '
      'aliases: $aliases, canEdit: $canEdit, '
      'homeserverDomain: $homeserverDomain)';
}

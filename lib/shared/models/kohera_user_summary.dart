import 'package:flutter/foundation.dart';

/// A Kohera-owned domain model representing a Matrix user with pre-computed
/// display fields.
///
/// This is the foundation model for member and avatar widgets. It carries no
/// `package:matrix/matrix.dart` dependency — the SDK `User` is converted to this
/// type at the conversion boundary (e.g. `RoomMembersSection`, `showMemberSheet`).
///
/// `KoheraRoomMember` (slice #10 of epic #697) will extend this with
/// `membership` and `powerLevel` fields.
@immutable
class KoheraUserSummary {
  const KoheraUserSummary({
    required this.userId,
    required this.displayname,
    this.avatarUrl,
  });

  /// The Matrix user ID (e.g. `@alice:example.com`).
  final String userId;

  /// The resolved display name. Produced by `User.calcDisplayname()` at the
  /// conversion boundary — never null (falls back to the user ID).
  final String displayname;

  /// The raw `mxc://` avatar URI as a string, or `null` if the user has no
  /// avatar. Resolved to an HTTP thumbnail URL by [AvatarResolver] at render
  /// time.
  final String? avatarUrl;

  KoheraUserSummary copyWith({
    String? userId,
    String? displayname,
    String? avatarUrl,
  }) =>
      KoheraUserSummary(
        userId: userId ?? this.userId,
        displayname: displayname ?? this.displayname,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraUserSummary &&
          userId == other.userId &&
          displayname == other.displayname &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode =>
      Object.hash(userId, displayname, avatarUrl);

  @override
  String toString() =>
      'KoheraUserSummary(userId: $userId, displayname: $displayname, '
      'avatarUrl: $avatarUrl)';
}

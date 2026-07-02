import 'package:kohera/shared/models/kohera_user_summary.dart';
import 'package:matrix/matrix.dart';

/// Converts a Matrix SDK [User] into a [KoheraUserSummary] domain model.
///
/// This is the single conversion boundary for `User` → `KoheraUserSummary`.
/// It calls `user.calcDisplayname()` once (which resolves the room profile
/// display name) and reads `user.avatarUrl` / `user.id`.
///
/// Call this wherever `User` objects are obtained from the SDK
/// (room participants, typing users, read receipt users).
KoheraUserSummary toKoheraUserSummary(User user) => KoheraUserSummary(
      userId: user.id,
      displayname: user.calcDisplayname(),
      avatarUrl: user.avatarUrl?.toString(),
    );

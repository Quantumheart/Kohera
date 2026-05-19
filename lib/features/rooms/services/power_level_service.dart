import 'package:matrix/matrix.dart';

/// A partial update to a room's `m.room.power_levels` state event.
///
/// Only non-null fields are merged into the existing content.
/// Map fields ([users], [events], [notifications]) are merged entry-by-entry,
/// so callers only need to supply the keys they want to change.
class PowerLevelPatch {
  const PowerLevelPatch({
    this.usersDefault,
    this.eventsDefault,
    this.stateDefault,
    this.invite,
    this.kick,
    this.ban,
    this.redact,
    this.users,
    this.events,
    this.notifications,
  });

  final int? usersDefault;
  final int? eventsDefault;
  final int? stateDefault;
  final int? invite;
  final int? kick;
  final int? ban;
  final int? redact;

  /// Per-user power level overrides to merge (keyed by Matrix ID).
  final Map<String, int>? users;

  /// Per-event-type power level overrides to merge (keyed by event type).
  final Map<String, int>? events;

  /// Per-notification key overrides to merge (e.g. `{"room": 50}`).
  final Map<String, int>? notifications;

  bool get isEmpty =>
      usersDefault == null &&
      eventsDefault == null &&
      stateDefault == null &&
      invite == null &&
      kick == null &&
      ban == null &&
      redact == null &&
      (users == null || users!.isEmpty) &&
      (events == null || events!.isEmpty) &&
      (notifications == null || notifications!.isEmpty);
}

/// Thrown when the server rejects a power-level write.
class PowerLevelException implements Exception {
  const PowerLevelException(this.message, {this.errcode});

  final String message;

  /// The Matrix errcode if available (e.g. `M_FORBIDDEN`).
  final String? errcode;

  @override
  String toString() =>
      errcode != null ? '$errcode: $message' : 'PowerLevelException: $message';
}

/// Reads the current `m.room.power_levels` state, merges [patch], and
/// writes back a single updated state event.
///
/// Fields not present in [patch] are preserved exactly as-is.
/// Throws [PowerLevelException] on `M_FORBIDDEN` or other server errors.
/// Does nothing if [patch] is empty.
class PowerLevelService {
  const PowerLevelService._();

  static Future<void> update(Room room, PowerLevelPatch patch) async {
    if (patch.isEmpty) return;

    final current =
        room.getState(EventTypes.RoomPowerLevels)?.content.copy() ?? {};

    _applyScalar(current, 'users_default', patch.usersDefault);
    _applyScalar(current, 'events_default', patch.eventsDefault);
    _applyScalar(current, 'state_default', patch.stateDefault);
    _applyScalar(current, 'invite', patch.invite);
    _applyScalar(current, 'kick', patch.kick);
    _applyScalar(current, 'ban', patch.ban);
    _applyScalar(current, 'redact', patch.redact);

    _mergeMap(current, 'users', patch.users);
    _mergeMap(current, 'events', patch.events);
    _mergeMap(current, 'notifications', patch.notifications);

    try {
      await room.client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomPowerLevels,
        '',
        current,
      );
    } on MatrixException catch (e) {
      throw PowerLevelException(e.errorMessage, errcode: e.errcode);
    }
  }

  static void _applyScalar(
    Map<String, Object?> content,
    String key,
    int? value,
  ) {
    if (value != null) content[key] = value;
  }

  static void _mergeMap(
    Map<String, Object?> content,
    String key,
    Map<String, int>? patch,
  ) {
    if (patch == null || patch.isEmpty) return;
    final existing =
        (content[key] as Map<String, Object?>?) ?? <String, Object?>{};
    existing.addAll(patch.map(MapEntry.new));
    content[key] = existing;
  }
}

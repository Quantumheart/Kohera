/// Matrix wire event-type constants, SDK-free.
///
/// Mirror the SDK `EventTypes`/`PollEventContent` strings the feature layer
/// needs, so feature files can match on event type without importing the
/// matrix SDK.
abstract class KoheraEventTypes {
  static const String message = 'm.room.message';
  static const String encrypted = 'm.room.encrypted';
  static const String encryption = 'm.room.encryption';
  static const String roomMember = 'm.room.member';
  static const String roomName = 'm.room.name';
  static const String roomTopic = 'm.room.topic';
  static const String roomAvatar = 'm.room.avatar';
  static const String roomTombstone = 'm.room.tombstone';
  static const String sticker = 'm.sticker';
  static const String roomPowerLevels = 'm.room.power_levels';
  static const String roomJoinRules = 'm.room.join_rules';
  static const String spaceChild = 'm.space.child';
  static const String receipt = 'm.receipt';
  static const String pollStart = 'org.matrix.msc3381.poll.start';
  static const String callMemberMsc = 'org.matrix.msc3401.call.member';
}

/// Matrix `m.relates_to` relationship-type constants, SDK-free.
abstract class KoheraRelationshipTypes {
  static const String thread = 'm.thread';
  static const String edit = 'm.replace';
  static const String reaction = 'm.annotation';
  static const String reference = 'm.reference';
}

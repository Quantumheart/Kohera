/// Matrix wire event-type constants, SDK-free.
///
/// Mirror the SDK `EventTypes`/`PollEventContent` strings the feature layer
/// needs, so feature files can match on event type without importing the
/// matrix SDK.
abstract class KoheraEventTypes {
  static const String message = 'm.room.message';
  static const String encrypted = 'm.room.encrypted';
  static const String roomMember = 'm.room.member';
  static const String receipt = 'm.receipt';
  static const String pollStart = 'org.matrix.msc3381.poll.start';
  static const String callMemberMsc = 'org.matrix.msc3401.call.member';
}

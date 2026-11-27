/// SDK-free legacy call signaling events.
///
/// `m.call.invite` in a direct chat is rendered as a missed-call marker
/// instead of establishing a call.
library;

sealed class KoheraSignalingEvent {}

class KoheraLegacyCallAttempt extends KoheraSignalingEvent {
  KoheraLegacyCallAttempt({required this.roomId, required this.senderId});

  final String roomId;
  final String senderId;
}

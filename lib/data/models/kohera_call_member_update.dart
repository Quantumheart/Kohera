/// SDK-free payload for an `org.matrix.msc3401.call.member` state update.
library;

class KoheraCallMemberUpdate {
  const KoheraCallMemberUpdate({
    required this.roomId,
    required this.stateKey,
    required this.content,
  });

  final String roomId;
  final String? stateKey;
  final Map<String, Object?> content;
}

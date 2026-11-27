/// SDK-free snapshot of one `org.matrix.msc3401.call.member` state event.
library;

class KoheraCallMemberState {
  const KoheraCallMemberState({
    required this.stateKey,
    required this.senderId,
    required this.content,
    this.originTsMs,
  });

  final String stateKey;
  final String senderId;
  final Map<String, dynamic> content;

  /// Event origin timestamp in milliseconds; null when unavailable, which
  /// callers treat as "now".
  final int? originTsMs;
}

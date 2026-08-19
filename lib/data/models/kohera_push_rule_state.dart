/// SDK-free representation of a Matrix push rule state for a room.
///
/// Mirrors `matrix_sdk.PushRuleState` without carrying a
/// `package:matrix/matrix.dart` dependency. The conversion boundary
/// ([RoomDetailsController]) maps between this and the SDK enum.
enum KoheraPushRuleState {
  notify,
  mentionsOnly,
  dontNotify,
}

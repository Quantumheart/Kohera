/// SDK-free representation of a Matrix push rule state for a room.
///
/// Mirrors `matrix_sdk.PushRuleState` without carrying a
/// `package:matrix/matrix.dart` dependency. The conversion boundary
/// (repositories) maps between this and the SDK enum.
enum KoheraPushRuleState {
  notify,
  mentionsOnly,
  dontNotify;

  /// Converts the SDK `PushRuleState` to [KoheraPushRuleState].
  ///
  /// Accepts any value (typed as `Object`) to avoid importing the SDK enum.
  static KoheraPushRuleState fromSdk(Object sdkState) {
    // Use toString() to avoid relying on the .name getter which may not
    // be available on all SDK enum implementations.
    final str = sdkState.toString();
    final name = str.substring(str.lastIndexOf('.') + 1);
    return switch (name) {
      'notify' => KoheraPushRuleState.notify,
      'mentionsOnly' => KoheraPushRuleState.mentionsOnly,
      'dontNotify' => KoheraPushRuleState.dontNotify,
      _ => KoheraPushRuleState.notify,
    };
  }
}

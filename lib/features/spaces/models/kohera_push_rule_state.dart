/// Kohera-owned push-rule state enum, decoupled from `package:matrix/matrix.dart`.
///
/// Convert to/from the SDK `PushRuleState` at the service boundary.
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

/// Kohera-owned mirror of the Matrix SDK `KeyVerificationState`.
///
/// The widget tree switches on this enum, so it carries the full SDK state
/// set rather than the reduced set in issue #711's spec — mapping to a
/// smaller enum would lose states the UI renders. The conversion boundary
/// (`KoheraKeyVerification`) maps SDK `KeyVerificationState` → this enum on
/// each `onUpdate`.
enum KoheraVerificationState {
  askChoice,
  askAccept,
  askSSSS,
  waitingAccept,
  askSas,
  showQRSuccess,
  confirmQRScan,
  waitingSas,
  done,
  error,
}

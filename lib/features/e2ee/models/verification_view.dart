/// Local sub-views layered on top of [KoheraVerificationState] while the user
/// is choosing how to verify ([KoheraVerificationState.askChoice]).
///
/// SDK-free; moved out of the (now-deleted) `KeyVerificationController` so the
/// verification widgets never import the Matrix SDK.
enum VerificationView { standard, chooser, showQr, scanQr }

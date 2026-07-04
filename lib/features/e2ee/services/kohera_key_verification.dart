import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/e2ee/models/kohera_verification_emoji.dart';
import 'package:kohera/features/e2ee/models/kohera_verification_state.dart';
import 'package:kohera/features/e2ee/models/verification_view.dart';
import 'package:kohera/features/e2ee/widgets/qr_verification_views.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Drives a single key-verification session for the dialog and inline hosts,
/// exposing an SDK-free surface so the verification widgets never import
/// `package:matrix`.
///
/// This is the conversion boundary — the only file in the E2EE verification
/// path that touches the Matrix SDK. It wraps a live [KeyVerification] object,
/// subscribes to its `onUpdate` callback, and re-exposes the full state, SAS
/// (emoji/numbers) data, QR data, capability flags, and actions the UI binds to.
/// Widgets watch this [ChangeNotifier]; they never see the SDK object.
///
/// Construct at the boundary where an SDK [KeyVerification] is obtained
/// (`verification_request_listener`, `room_details_controller`,
/// `devices_screen`, `e2ee_setup_screen`) and pass this wrapper to the
/// verification widgets.
class KoheraKeyVerification extends ChangeNotifier {
  KoheraKeyVerification(KeyVerification verification) : _verification = verification {
    verification.onUpdate = _onUpdate;
    state = _mapState(verification.state);
    _resolveView(state);
  }

  final KeyVerification _verification;

  KoheraVerificationState state = KoheraVerificationState.waitingAccept;
  VerificationView view = VerificationView.standard;

  // ── Identity ────────────────────────────────────────────────

  /// The other party's Matrix user ID.
  String get otherUserId => _verification.userId;

  /// The other party's device ID, if known.
  String? get otherDeviceId => _verification.deviceId;

  /// Whether this verification is with our own user (another of our devices).
  bool get isMe => _verification.client.userID == _verification.userId;

  /// The cancel/failure reason, if any.
  String? get canceledReason => _verification.canceledReason;

  // ── SAS data ────────────────────────────────────────────────

  /// The negotiated SAS types (e.g. `emoji`, `decimal`).
  List<String> get sasTypes => _verification.sasTypes;

  /// The SAS decimal numbers to compare, when negotiated.
  List<int> get sasNumbers => _verification.sasNumbers;

  /// The SAS emoji to compare, as SDK-free [KoheraVerificationEmoji]s.
  List<KoheraVerificationEmoji> get sasEmojis => _verification.sasEmojis
      .map((e) => KoheraVerificationEmoji(emoji: e.emoji, name: e.name))
      .toList();

  /// Whether to show the decimal SAS representation (negotiated and present).
  bool get showsSasNumbers {
    final types = sasTypes;
    final decimalNegotiated = types.isEmpty || types.contains('decimal');
    return decimalNegotiated && sasNumbers.isNotEmpty;
  }

  // ── QR data ─────────────────────────────────────────────────

  /// The raw QR code bytes to display when showing a QR code, or `null`.
  Uint8List? get qrDataRawBytes {
    final qr = _verification.qrCode;
    return qr == null ? null : Uint8List.fromList(qr.qrDataRawBytes);
  }

  // ── Capability flags ────────────────────────────────────────

  bool get canShowQr =>
      _verification.possibleMethods.contains(EventTypes.QRShow) &&
      _verification.qrCode != null;

  bool get canScanQr =>
      _verification.possibleMethods.contains(EventTypes.QRScan) &&
      qrScanSupported;

  bool get canCompareSas => _verification.possibleMethods.contains(EventTypes.Sas);

  // ── State mapping + view resolution ─────────────────────────

  void _onUpdate() {
    state = _mapState(_verification.state);
    _resolveView(state);
    notifyListeners();
  }

  KoheraVerificationState _mapState(KeyVerificationState s) {
    switch (s) {
      case KeyVerificationState.askChoice:
        return KoheraVerificationState.askChoice;
      case KeyVerificationState.askAccept:
        return KoheraVerificationState.askAccept;
      case KeyVerificationState.askSSSS:
        return KoheraVerificationState.askSSSS;
      case KeyVerificationState.waitingAccept:
        return KoheraVerificationState.waitingAccept;
      case KeyVerificationState.askSas:
        return KoheraVerificationState.askSas;
      case KeyVerificationState.showQRSuccess:
        return KoheraVerificationState.showQRSuccess;
      case KeyVerificationState.confirmQRScan:
        return KoheraVerificationState.confirmQRScan;
      case KeyVerificationState.waitingSas:
        return KoheraVerificationState.waitingSas;
      case KeyVerificationState.done:
        return KoheraVerificationState.done;
      case KeyVerificationState.error:
        return KoheraVerificationState.error;
    }
  }

  void _resolveView(KoheraVerificationState s) {
    if (s != KoheraVerificationState.askChoice) {
      view = VerificationView.standard;
      return;
    }
    if (!canShowQr && !canScanQr) {
      view = VerificationView.standard;
      if (canCompareSas) {
        debugPrint('[Kohera] Verification: no QR available, selecting SAS');
        unawaited(_verification.continueVerification(EventTypes.Sas));
      }
      return;
    }
    view = VerificationView.chooser;
  }

  // ── UI sub-view actions ─────────────────────────────────────

  void chooseShowQr() {
    view = VerificationView.showQr;
    notifyListeners();
  }

  void chooseScanQr() {
    view = VerificationView.scanQr;
    notifyListeners();
  }

  void chooseCompareSas() {
    view = VerificationView.standard;
    notifyListeners();
    unawaited(_verification.continueVerification(EventTypes.Sas));
  }

  void onQrScanned(Uint8List bytes) {
    unawaited(
      _verification.continueVerification(
        EventTypes.Reciprocate,
        qrDataRawBytes: bytes,
      ),
    );
  }

  // ── Verification flow actions (proxy to SDK) ────────────────

  Future<void> acceptVerification() => _verification.acceptVerification();

  Future<void> rejectSas() => _verification.rejectSas();

  Future<void> acceptSas() => _verification.acceptSas();

  Future<void> acceptQRScanConfirmation() =>
      _verification.acceptQRScanConfirmation();

  Future<void> cancel([String code = 'm.unknown', bool quiet = false]) =>
      _verification.cancel(code, quiet);

  @override
  void dispose() {
    _verification.onUpdate = null;
    super.dispose();
  }
}

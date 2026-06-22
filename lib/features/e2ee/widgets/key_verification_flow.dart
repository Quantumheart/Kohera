import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/e2ee/widgets/qr_verification_views.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Local sub-views layered on top of the SDK's [KeyVerificationState] while the
/// user is choosing how to verify ([KeyVerificationState.askChoice]).
enum VerificationView { standard, chooser, showQr, scanQr }

/// Drives a single key-verification session for the dialog and inline hosts.
///
/// Owns the [KeyVerification.onUpdate] subscription, the current SDK state, and
/// the QR sub-view, and exposes the actions the UI binds to (choose to scan,
/// show, or compare numbers). Hosts listen via [ChangeNotifier] and supply
/// only their own chrome and done/cancel handling.
class KeyVerificationController extends ChangeNotifier {
  KeyVerificationController(this.verification) {
    verification.onUpdate = _onVerificationUpdate;
    verificationState = verification.state;
    _resolveView(verificationState);
  }

  final KeyVerification verification;

  KeyVerificationState verificationState = KeyVerificationState.waitingAccept;
  VerificationView view = VerificationView.standard;

  bool get canShowQr =>
      verification.possibleMethods.contains(EventTypes.QRShow) &&
      verification.qrCode != null;

  bool get canScanQr =>
      verification.possibleMethods.contains(EventTypes.QRScan) &&
      qrScanSupported;

  bool get canCompareSas =>
      verification.possibleMethods.contains(EventTypes.Sas);

  void _onVerificationUpdate() {
    verificationState = verification.state;
    _resolveView(verificationState);
    notifyListeners();
  }

  void _resolveView(KeyVerificationState state) {
    if (state != KeyVerificationState.askChoice) {
      view = VerificationView.standard;
      return;
    }
    if (!canShowQr && !canScanQr) {
      // No QR path available between these devices: keep the previous
      // friction-free behaviour and compare numbers/emoji automatically.
      view = VerificationView.standard;
      if (canCompareSas) {
        debugPrint('[Kohera] Verification: no QR available, selecting SAS');
        unawaited(verification.continueVerification(EventTypes.Sas));
      }
      return;
    }
    view = VerificationView.chooser;
  }

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
    unawaited(verification.continueVerification(EventTypes.Sas));
  }

  void onQrScanned(Uint8List bytes) {
    unawaited(
      verification.continueVerification(
        EventTypes.Reciprocate,
        qrDataRawBytes: bytes,
      ),
    );
  }

  @override
  void dispose() {
    verification.onUpdate = null;
    super.dispose();
  }
}

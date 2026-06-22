import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kohera/features/e2ee/widgets/qr_verification_views.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Local sub-views layered on top of the SDK's [KeyVerificationState] while the
/// user is choosing how to verify ([KeyVerificationState.askChoice]).
enum VerificationView { standard, chooser, showQr, scanQr }

/// Shared verification-flow state for the dialog and inline hosts.
///
/// Owns the [KeyVerification.onUpdate] subscription, the current SDK state, and
/// the QR sub-view, and exposes the actions the UI binds to (choose to scan,
/// show, or compare emoji).
mixin KeyVerificationFlowMixin<T extends StatefulWidget> on State<T> {
  KeyVerification get verification;

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

  void initVerificationFlow() {
    verification.onUpdate = _onVerificationUpdate;
    verificationState = verification.state;
    _resolveView(verificationState);
  }

  void disposeVerificationFlow() {
    verification.onUpdate = null;
  }

  void _onVerificationUpdate() {
    if (!mounted) return;
    final newState = verification.state;
    _resolveView(newState);
    setState(() => verificationState = newState);
  }

  void _resolveView(KeyVerificationState state) {
    if (state != KeyVerificationState.askChoice) {
      view = VerificationView.standard;
      return;
    }
    if (!canShowQr && !canScanQr) {
      // No QR path available between these devices: keep the previous
      // friction-free behaviour and compare emoji/numbers automatically.
      view = VerificationView.standard;
      if (canCompareSas) {
        debugPrint('[Kohera] Verification: no QR available, selecting SAS');
        unawaited(verification.continueVerification(EventTypes.Sas));
      }
      return;
    }
    view = VerificationView.chooser;
  }

  void chooseShowQr() => setState(() => view = VerificationView.showQr);

  void chooseScanQr() => setState(() => view = VerificationView.scanQr);

  void chooseCompareSas() {
    setState(() => view = VerificationView.standard);
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
}

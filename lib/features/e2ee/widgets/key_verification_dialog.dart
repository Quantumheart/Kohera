import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_content.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_flow.dart';
import 'package:matrix/encryption.dart';

class KeyVerificationDialog extends StatefulWidget {
  final KeyVerification verification;

  const KeyVerificationDialog({
    required this.verification, super.key,
  });

  static Future<bool?> show(
    BuildContext context, {
    required KeyVerification verification,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KeyVerificationDialog(verification: verification),
    );
  }

  @override
  State<KeyVerificationDialog> createState() => _KeyVerificationDialogState();
}

class _KeyVerificationDialogState extends State<KeyVerificationDialog>
    with KeyVerificationFlowMixin {
  @override
  KeyVerification get verification => widget.verification;

  @override
  void initState() {
    super.initState();
    initVerificationFlow();
  }

  @override
  void dispose() {
    disposeVerificationFlow();
    super.dispose();
  }

  void _cancel() {
    unawaited(verification.cancel());
    Navigator.pop(context, false);
  }

  void _done() {
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(verificationTitle(verificationState, view, verification)),
      content: SizedBox(
        width: 400,
        child: KeyVerificationContent(
          state: verificationState,
          verification: verification,
          view: view,
          onChooseShowQr: chooseShowQr,
          onChooseScanQr: chooseScanQr,
          onChooseCompareSas: chooseCompareSas,
          onScanned: onQrScanned,
        ),
      ),
      actions: buildVerificationActions(
        state: verificationState,
        verification: verification,
        view: view,
        onCancel: _cancel,
        onDone: _done,
      ),
    );
  }
}

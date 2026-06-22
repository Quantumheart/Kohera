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

class _KeyVerificationDialogState extends State<KeyVerificationDialog> {
  late final KeyVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = KeyVerificationController(widget.verification);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    unawaited(widget.verification.cancel());
    Navigator.pop(context, false);
  }

  void _done() {
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => AlertDialog(
        title: Text(
          verificationTitle(
            _controller.verificationState,
            _controller.view,
            widget.verification,
          ),
        ),
        content: SizedBox(
          width: 400,
          child: KeyVerificationContent(
            state: _controller.verificationState,
            verification: widget.verification,
            view: _controller.view,
            onChooseShowQr: _controller.chooseShowQr,
            onChooseScanQr: _controller.chooseScanQr,
            onChooseCompareSas: _controller.chooseCompareSas,
            onScanned: _controller.onQrScanned,
          ),
        ),
        actions: buildVerificationActions(
          state: _controller.verificationState,
          verification: widget.verification,
          view: _controller.view,
          onCancel: _cancel,
          onDone: _done,
        ),
      ),
    );
  }
}

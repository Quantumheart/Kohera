import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_content.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_flow.dart';
import 'package:matrix/encryption.dart';

class KeyVerificationInline extends StatefulWidget {
  const KeyVerificationInline({
    required this.verification,
    required this.onDone,
    required this.onCancel,
    super.key,
  });

  final KeyVerification verification;
  final ValueChanged<bool> onDone;
  final VoidCallback onCancel;

  @override
  State<KeyVerificationInline> createState() => _KeyVerificationInlineState();
}

class _KeyVerificationInlineState extends State<KeyVerificationInline>
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

  void _handleCancel() {
    unawaited(verification.cancel());
    widget.onCancel();
  }

  void _handleDone() {
    widget.onDone(verificationState == KeyVerificationState.done);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyVerificationContent(
          state: verificationState,
          verification: verification,
          view: view,
          onChooseShowQr: chooseShowQr,
          onChooseScanQr: chooseScanQr,
          onChooseCompareSas: chooseCompareSas,
          onScanned: onQrScanned,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: buildVerificationActions(
            state: verificationState,
            verification: verification,
            view: view,
            onCancel: _handleCancel,
            onDone: _handleDone,
          ).map((w) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: w,
          ),).toList(),
        ),
      ],
    );
  }
}

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

class _KeyVerificationInlineState extends State<KeyVerificationInline> {
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

  void _handleCancel() {
    unawaited(widget.verification.cancel());
    widget.onCancel();
  }

  void _handleDone() {
    widget.onDone(
      _controller.verificationState == KeyVerificationState.done,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyVerificationContent(
            state: _controller.verificationState,
            verification: widget.verification,
            view: _controller.view,
            onChooseShowQr: _controller.chooseShowQr,
            onChooseScanQr: _controller.chooseScanQr,
            onChooseCompareSas: _controller.chooseCompareSas,
            onScanned: _controller.onQrScanned,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: buildVerificationActions(
              state: _controller.verificationState,
              verification: widget.verification,
              view: _controller.view,
              onCancel: _handleCancel,
              onDone: _handleDone,
            ).map((w) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: w,
            ),).toList(),
          ),
        ],
      ),
    );
  }
}

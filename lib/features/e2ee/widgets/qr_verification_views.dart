import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ── QR verification platform support ────────────────────────────

/// Whether camera-based QR scanning is available on this platform.
///
/// `mobile_scanner` ships native implementations for Android, iOS, macOS and
/// web only. Linux and Windows can still *show* a QR code for another device
/// to scan, but cannot drive the camera themselves, so the scan option is
/// hidden there and verification falls back to showing a code or emoji.
bool get qrScanSupported {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      return false;
  }
}

// ── QR code display ─────────────────────────────────────────────

class QrCodeView extends StatelessWidget {
  const QrCodeView({required this.data, super.key});

  final Uint8List data;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Scan this code with your other device.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView.withQr(
            qr: QrCode.fromUint8List(
              data: data,
              errorCorrectLevel: QrErrorCorrectLevel.L,
            ),
            size: 220,
          ),
        ),
      ],
    );
  }
}

// ── QR code scanner ─────────────────────────────────────────────

class QrScannerView extends StatefulWidget {
  const QrScannerView({required this.onScanned, super.key});

  final ValueChanged<Uint8List> onScanned;

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final bytes = _bytesOf(barcode.rawDecodedBytes);
      if (bytes != null && bytes.isNotEmpty) {
        _handled = true;
        widget.onScanned(bytes);
        return;
      }
    }
  }

  Uint8List? _bytesOf(BarcodeBytes? raw) {
    switch (raw) {
      case DecodedBarcodeBytes(:final bytes):
        return bytes;
      case DecodedVisionBarcodeBytes(:final bytes, :final rawBytes):
        return bytes ?? rawBytes;
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Point the camera at the QR code on your other device.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 240,
            height: 240,
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
        ),
      ],
    );
  }
}

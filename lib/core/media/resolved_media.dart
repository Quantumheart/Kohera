import 'dart:typed_data';

// ── Resolved media (replaces media_kit Media) ─────────────────

class ResolvedMedia {
  const ResolvedMedia({this.filePath, this.bytes, this.mimeType});

  final String? filePath;
  final Uint8List? bytes;
  final String? mimeType;
}

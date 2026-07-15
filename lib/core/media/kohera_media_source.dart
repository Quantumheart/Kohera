import 'dart:typed_data';

// ── Platform-agnostic media source ────────────────────────────

sealed class KoheraMediaSource {
  const KoheraMediaSource();
}

class KoheraFileSource extends KoheraMediaSource {
  const KoheraFileSource(this.path);
  final String path;
}

class KoheraBytesSource extends KoheraMediaSource {
  const KoheraBytesSource(this.bytes, {this.mimeType});
  final Uint8List bytes;
  final String? mimeType;
}

class KoheraAssetSource extends KoheraMediaSource {
  const KoheraAssetSource(this.assetPath);
  final String assetPath;
}

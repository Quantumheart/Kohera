/// The result of resolving an `mxc://` URI to an HTTP URL with optional
/// authentication headers.
class MediaThumbnail {
  const MediaThumbnail({required this.url, this.headers});

  /// The resolved HTTP(S) URL (thumbnail or full download).
  final String url;

  /// Auth headers for authenticated media endpoints, or `null` if the
  /// endpoint does not require authentication.
  final Map<String, String>? headers;
}

/// Resolves `mxc://` media URIs to HTTP URLs with auth headers.
///
/// This abstraction decouples media-rendering widgets (e.g. [MxcImage]) from
/// `package:matrix/matrix.dart` — the concrete implementation
/// ([ClientMediaResolver]) wraps the Matrix `Client`, but widgets only
/// depend on this interface.
abstract interface class MediaResolver {
  /// Resolves [mxcUrl] (an `mxc://` URI string) to an HTTP URL.
  ///
  /// When [width] and [height] are both ≤ 96, a thumbnail URL is returned;
  /// otherwise a full-download URL is returned.
  ///
  /// Returns `null` if [mxcUrl] is null, not an `mxc://` URI, or resolution
  /// fails.
  Future<MediaThumbnail?> resolve(
    String? mxcUrl, {
    required double? width,
    required double? height,
  });
}

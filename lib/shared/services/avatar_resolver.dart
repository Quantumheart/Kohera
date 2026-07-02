/// The result of resolving an `mxc://` avatar URI to an HTTP thumbnail URL
/// with optional authentication headers.
class AvatarThumbnail {
  const AvatarThumbnail({required this.url, this.headers});

  /// The resolved HTTP(S) thumbnail URL.
  final String url;

  /// Auth headers for authenticated media endpoints, or `null` if the
  /// endpoint does not require authentication.
  final Map<String, String>? headers;
}

/// Resolves `mxc://` avatar URIs to HTTP thumbnail URLs with auth headers.
///
/// This abstraction decouples avatar-rendering widgets from
/// `package:matrix/matrix.dart` — the concrete implementation
/// ([ClientAvatarResolver]) wraps the Matrix `Client`, but widgets only
/// depend on this interface.
abstract interface class AvatarResolver {
  /// Resolves [mxcUrl] (an `mxc://` URI string) to a thumbnail URL sized for
  /// [size] pixels (the resolver doubles the dimension for retina).
  ///
  /// Returns `null` if [mxcUrl] is null or resolution fails.
  Future<AvatarThumbnail?> resolve(String? mxcUrl, {required double size});
}

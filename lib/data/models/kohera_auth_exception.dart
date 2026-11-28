/// Thrown when the homeserver rejects an authenticated account operation.
///
/// SDK-free replacement for catching `MatrixException` in the feature layer.
class KoheraAuthException implements Exception {
  const KoheraAuthException(this.message, {this.errcode, this.raw = const {}});

  /// The human-readable error message from the homeserver.
  final String message;

  /// The Matrix errcode if available (e.g. `M_FORBIDDEN`).
  final String? errcode;

  /// The raw error payload, e.g. the UIA challenge (`flows`, `session`,
  /// `completed`) for registration.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      errcode != null ? '$errcode: $message' : 'KoheraAuthException: $message';
}

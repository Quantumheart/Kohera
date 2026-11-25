/// Thrown when the homeserver rejects an upload for exceeding its size limit.
class KoheraFileTooBigException implements Exception {
  const KoheraFileTooBigException(this.fileName);

  /// The name of the file that exceeded the server limit.
  final String fileName;

  @override
  String toString() => 'KoheraFileTooBigException: $fileName';
}

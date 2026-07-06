/// Kohera-owned presence type enum, mirroring `matrix.PresenceType`
/// without importing the Matrix SDK.
enum KoheraPresenceType {
  online,
  unavailable,
  offline;

  /// Converts from the SDK enum's `.name` string value.
  ///
  /// Use as: `KoheraPresenceType.fromName(cached.presence.name)`
  /// where `cached.presence` is an inferred `PresenceType`.
  factory KoheraPresenceType.fromName(String name) => switch (name) {
        'online' => KoheraPresenceType.online,
        'unavailable' => KoheraPresenceType.unavailable,
        _ => KoheraPresenceType.offline,
      };
}

import 'package:flutter/foundation.dart';

/// A single SAS (short authentication string) emoji shown during key
/// verification, with its glyph and human-readable name.
///
/// SDK-free mirror of the Matrix SDK `KeyVerificationEmoji`. The conversion
/// boundary (`KoheraKeyVerification`) maps each SDK emoji to this type so the
/// verification widgets never import `package:matrix`.
@immutable
class KoheraVerificationEmoji {
  const KoheraVerificationEmoji({required this.emoji, required this.name});

  /// The emoji glyph (e.g. 🐶).
  final String emoji;

  /// The emoji's display name (e.g. `Dog`), used for semantics.
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraVerificationEmoji &&
          emoji == other.emoji &&
          name == other.name;

  @override
  int get hashCode => Object.hash(emoji, name);

  @override
  String toString() => 'KoheraVerificationEmoji($emoji, $name)';
}

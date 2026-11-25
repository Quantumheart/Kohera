import 'package:flutter/foundation.dart';

/// SDK-free result of decrypting an encrypted event.
@immutable
class KoheraDecryptedEvent {
  const KoheraDecryptedEvent({
    required this.type,
    required this.body,
    required this.content,
  });

  /// The decrypted wire event type.
  final String type;

  /// The decrypted `body` content field, or an empty string.
  final String body;

  /// The decrypted event content.
  final Map<String, Object?> content;
}

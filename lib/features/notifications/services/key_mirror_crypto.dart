import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-256-GCM used to protect the iOS key-mirror payloads at rest.
///
/// [encrypt] returns `nonce || ciphertext || tag`, matching CryptoKit's
/// combined `AES.GCM.SealedBox` representation so the Notification Service
/// Extension can decrypt with `AES.GCM.open`.
class KeyMirrorCrypto {
  static const int keyLength = 32;
  static const int _nonceLength = 12;
  static const int _macBits = 128;

  static final Random _random = Random.secure();

  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static Uint8List generateKey() => randomBytes(keyLength);

  static Uint8List encrypt(Uint8List key, Uint8List plaintext) {
    final nonce = randomBytes(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)),
      );
    final sealed = cipher.process(plaintext);
    return Uint8List.fromList([...nonce, ...sealed]);
  }

  static Uint8List decrypt(Uint8List key, Uint8List combined) {
    final nonce = Uint8List.sublistView(combined, 0, _nonceLength);
    final sealed = Uint8List.sublistView(combined, _nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)),
      );
    return cipher.process(sealed);
  }
}

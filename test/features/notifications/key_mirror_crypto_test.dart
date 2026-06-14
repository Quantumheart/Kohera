import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/notifications/services/key_mirror_crypto.dart';

void main() {
  group('KeyMirrorCrypto', () {
    test('generateKey returns 32 random bytes', () {
      final a = KeyMirrorCrypto.generateKey();
      final b = KeyMirrorCrypto.generateKey();
      expect(a.length, KeyMirrorCrypto.keyLength);
      expect(a, isNot(equals(b)));
    });

    test('round-trips a payload', () {
      final key = KeyMirrorCrypto.generateKey();
      final plaintext =
          Uint8List.fromList(utf8.encode('{"pickle":"secret-session"}'));

      final sealed = KeyMirrorCrypto.encrypt(key, plaintext);
      final opened = KeyMirrorCrypto.decrypt(key, sealed);

      expect(opened, equals(plaintext));
    });

    test('output is nonce(12) + ciphertext + tag(16), CryptoKit-combined', () {
      final key = KeyMirrorCrypto.generateKey();
      final plaintext = Uint8List.fromList(utf8.encode('hello'));

      final sealed = KeyMirrorCrypto.encrypt(key, plaintext);

      // 12-byte nonce + ciphertext (== plaintext length for GCM) + 16-byte tag.
      expect(sealed.length, 12 + plaintext.length + 16);
    });

    test('uses a fresh nonce per encryption', () {
      final key = KeyMirrorCrypto.generateKey();
      final plaintext = Uint8List.fromList(utf8.encode('same input'));

      final first = KeyMirrorCrypto.encrypt(key, plaintext);
      final second = KeyMirrorCrypto.encrypt(key, plaintext);

      expect(first, isNot(equals(second)));
    });

    test('rejects decryption with the wrong key', () {
      final plaintext = Uint8List.fromList(utf8.encode('top secret'));
      final sealed = KeyMirrorCrypto.encrypt(
        KeyMirrorCrypto.generateKey(),
        plaintext,
      );

      expect(
        () => KeyMirrorCrypto.decrypt(KeyMirrorCrypto.generateKey(), sealed),
        throwsA(anything),
      );
    });

    test('rejects a tampered ciphertext', () {
      final key = KeyMirrorCrypto.generateKey();
      final sealed = KeyMirrorCrypto.encrypt(
        key,
        Uint8List.fromList(utf8.encode('integrity')),
      );
      sealed[sealed.length - 1] ^= 0xFF;

      expect(
        () => KeyMirrorCrypto.decrypt(key, sealed),
        throwsA(anything),
      );
    });
  });
}

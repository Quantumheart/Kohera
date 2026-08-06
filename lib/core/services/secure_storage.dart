import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [FlutterSecureStorage] wrapper that falls back to an in-memory store when
/// the platform keyring is locked (Linux) or otherwise unavailable.
///
/// This lets the app start on Linux desktops that do not have an unlocked
/// libsecret keyring, at the cost of credentials not persisting across app
/// restarts in that configuration.
class KoheraSecureStorage extends FlutterSecureStorage {
  KoheraSecureStorage({
    super.iOptions,
    super.aOptions,
    super.lOptions,
    super.wOptions,
    super.webOptions,
    super.mOptions,
  });

  final Map<String, String> _fallback = {};
  bool _useFallback = false;

  Future<T> _withFallback<T>(
    Future<T> Function() attempt,
    T Function() fallback,
  ) async {
    if (_useFallback) return fallback();
    try {
      return await attempt();
    } on PlatformException catch (e) {
      if (e.code == 'KeyringLocked') {
        debugPrint(
          '[Kohera] Keyring locked; using in-memory secure storage fallback. '
          'Credentials will not persist across app restarts.',
        );
        _useFallback = true;
        return fallback();
      }
      rethrow;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _withFallback(
    () => super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
    () => _fallback[key],
  );

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _withFallback(
    () => super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
    () {
      if (value == null) {
        _fallback.remove(key);
      } else {
        _fallback[key] = value;
      }
    },
  );

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _withFallback(
    () => super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
    () => _fallback.remove(key),
  );

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _withFallback(
    () => super.containsKey(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
    () => _fallback.containsKey(key),
  );

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _withFallback(
    () => super.readAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
    () => Map.unmodifiable(_fallback),
  );

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _withFallback(
    () => super.deleteAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
    _fallback.clear,
  );
}

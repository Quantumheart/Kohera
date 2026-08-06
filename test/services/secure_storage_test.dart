import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/secure_storage.dart';

class _LockedKeyringPlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<void> deleteAll({required Map<String, String> options}) => _throw();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _throw();

  Future<T> _throw<T>() async => throw PlatformException(
    code: 'KeyringLocked',
    message: 'KeyringLocked',
  );
}

class _OtherErrorPlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<void> deleteAll({required Map<String, String> options}) => _throw();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) => _throw();

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _throw();

  Future<T> _throw<T>() async => throw PlatformException(
    code: 'SomeOtherError',
    message: 'SomeOtherError',
  );
}

void main() {
  group('KoheraSecureStorage', () {
    late FlutterSecureStoragePlatform originalPlatform;

    setUpAll(() {
      originalPlatform = FlutterSecureStoragePlatform.instance;
    });

    tearDown(() {
      FlutterSecureStoragePlatform.instance = originalPlatform;
    });

    test('read falls back to in-memory when keyring is locked', () async {
      FlutterSecureStoragePlatform.instance = _LockedKeyringPlatform();
      final storage = KoheraSecureStorage();

      expect(await storage.read(key: 'foo'), isNull);
      await storage.write(key: 'foo', value: 'bar');
      expect(await storage.read(key: 'foo'), 'bar');
    });

    test('delete removes value from in-memory fallback', () async {
      FlutterSecureStoragePlatform.instance = _LockedKeyringPlatform();
      final storage = KoheraSecureStorage();

      await storage.write(key: 'foo', value: 'bar');
      expect(await storage.read(key: 'foo'), 'bar');
      await storage.delete(key: 'foo');
      expect(await storage.read(key: 'foo'), isNull);
    });

    test('containsKey works with in-memory fallback', () async {
      FlutterSecureStoragePlatform.instance = _LockedKeyringPlatform();
      final storage = KoheraSecureStorage();

      expect(await storage.containsKey(key: 'foo'), false);
      await storage.write(key: 'foo', value: 'bar');
      expect(await storage.containsKey(key: 'foo'), true);
    });

    test('readAll returns in-memory values when keyring is locked', () async {
      FlutterSecureStoragePlatform.instance = _LockedKeyringPlatform();
      final storage = KoheraSecureStorage();

      await storage.write(key: 'foo', value: 'bar');
      await storage.write(key: 'baz', value: 'qux');
      expect(await storage.readAll(), {'foo': 'bar', 'baz': 'qux'});
    });

    test('deleteAll clears in-memory fallback', () async {
      FlutterSecureStoragePlatform.instance = _LockedKeyringPlatform();
      final storage = KoheraSecureStorage();

      await storage.write(key: 'foo', value: 'bar');
      await storage.deleteAll();
      expect(await storage.read(key: 'foo'), isNull);
      expect(await storage.readAll(), isEmpty);
    });

    test('rethrows non-keyring PlatformException', () async {
      FlutterSecureStoragePlatform.instance = _OtherErrorPlatform();
      final storage = KoheraSecureStorage();

      expect(
        () => storage.read(key: 'foo'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('write with null value removes key in fallback', () async {
      FlutterSecureStoragePlatform.instance = _LockedKeyringPlatform();
      final storage = KoheraSecureStorage();

      await storage.write(key: 'foo', value: 'bar');
      await storage.write(key: 'foo', value: null);
      expect(await storage.read(key: 'foo'), isNull);
    });
  });
}

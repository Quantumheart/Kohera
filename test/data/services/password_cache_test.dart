import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/services/password_cache.dart';

void main() {
  late PasswordCache cache;

  setUp(() {
    cache = PasswordCache();
  });

  group('setCachedPassword', () {
    test('holds the password until it expires', () {
      fakeAsync((async) {
        cache.setCachedPassword('secret');
        expect(cache.cachedPassword, 'secret');

        async.elapse(const Duration(seconds: 31));
        expect(cache.cachedPassword, isNull);
      });
    });
  });

  group('clearCachedPassword', () {
    test('clears immediately', () {
      cache.setCachedPassword('secret');
      cache.clearCachedPassword();
      expect(cache.cachedPassword, isNull);
    });
  });
}

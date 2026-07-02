import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/models/kohera_user_summary.dart';

void main() {
  group('KoheraUserSummary', () {
    test('constructs with required fields', () {
      const user = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/avatar123',
      );

      expect(user.userId, '@alice:example.com');
      expect(user.displayname, 'Alice');
      expect(user.avatarUrl, 'mxc://example.com/avatar123');
    });

    test('constructs with null avatarUrl', () {
      const user = KoheraUserSummary(
        userId: '@bob:example.com',
        displayname: 'Bob',
      );

      expect(user.avatarUrl, isNull);
    });

    test('equality based on all fields', () {
      const a = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/abc',
      );
      const b = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/abc',
      );
      const c = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alicia',
        avatarUrl: 'mxc://example.com/abc',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });

    test('copyWith updates fields', () {
      const user = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/old',
      );

      final updated = user.copyWith(
        displayname: 'Alicia',
        avatarUrl: 'mxc://example.com/new',
      );

      expect(updated.userId, '@alice:example.com');
      expect(updated.displayname, 'Alicia');
      expect(updated.avatarUrl, 'mxc://example.com/new');
    });

    test('copyWith preserves unchanged fields', () {
      const user = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/abc',
      );

      final updated = user.copyWith(displayname: 'Alicia');

      expect(updated.userId, '@alice:example.com');
      expect(updated.displayname, 'Alicia');
      expect(updated.avatarUrl, 'mxc://example.com/abc');
    });

    test('toString contains all fields', () {
      const user = KoheraUserSummary(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/abc',
      );

      final str = user.toString();
      expect(str, contains('@alice:example.com'));
      expect(str, contains('Alice'));
      expect(str, contains('mxc://example.com/abc'));
    });
  });
}

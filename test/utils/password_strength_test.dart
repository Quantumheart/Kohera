import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/password_strength.dart';

void main() {
  group('assessPassword', () {
    test('reports empty for an empty password', () {
      final result = assessPassword('');

      expect(result.strength, PasswordStrength.empty);
      expect(result.score, 0);
      expect(result.meetsMinimum, isFalse);
    });

    test('rates a short password weak', () {
      final result = assessPassword('abc');

      expect(result.strength, PasswordStrength.weak);
      expect(result.meetsMinimum, isFalse);
      expect(result.suggestions,
          contains('Use at least $kMinimumPasswordLength characters'),);
    });

    test('rates a long mixed password strong', () {
      final result = assessPassword('Tr0ub4dor&3-Horse');

      expect(result.strength, PasswordStrength.strong);
      expect(result.score, 1.0);
      expect(result.meetsMinimum, isTrue);
      expect(result.suggestions, isEmpty);
    });

    test('rates a common password weak regardless of length', () {
      final result = assessPassword('password123');

      expect(result.strength, PasswordStrength.weak);
      expect(result.suggestions, contains('Avoid common passwords'));
    });

    test('matches common passwords case-insensitively', () {
      expect(
        assessPassword('PassWord123').suggestions,
        contains('Avoid common passwords'),
      );
    });

    test('penalises repeated character runs', () {
      final withRun = assessPassword('Aaaa1234!x');

      expect(withRun.suggestions, contains('Avoid repeated characters'));
    });

    test('suggests the missing character classes', () {
      final lowerOnly = assessPassword('abcdefghij');

      expect(lowerOnly.suggestions, contains('Mix upper and lower case'));
      expect(lowerOnly.suggestions, contains('Add a number'));
      expect(lowerOnly.suggestions, contains('Add a symbol'));
    });

    test('score rises monotonically with strength', () {
      final ladder = [
        assessPassword('abc'),
        assessPassword('abcdefgh'),
        assessPassword('Abcdefgh1'),
        assessPassword('Abcdefgh1!xyz'),
      ].map((a) => a.score).toList();

      expect(ladder, orderedEquals(<double>[...ladder]..sort()));
    });

    test('suggestions are unmodifiable', () {
      expect(
        () => assessPassword('abc').suggestions.add('nope'),
        throwsUnsupportedError,
      );
    });
  });
}

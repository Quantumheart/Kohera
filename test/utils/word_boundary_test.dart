import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/word_boundary.dart';

void main() {
  group('containsWord', () {
    test('matches a word bounded by spaces', () {
      expect(containsWord('hey max, hello', 'max'), isTrue);
    });

    test('matches a word at string edges', () {
      expect(containsWord('max', 'max'), isTrue);
      expect(containsWord('max!', 'max'), isTrue);
      expect(containsWord('@max', 'max'), isTrue);
    });

    test('does not match inside a larger Latin word', () {
      expect(containsWord('maximum effort', 'max'), isFalse);
      expect(containsWord('climax', 'max'), isFalse);
      expect(containsWord('willpower wins', 'will'), isFalse);
    });

    test('treats digits and underscores as word characters', () {
      expect(containsWord('max99 said hi', 'max'), isFalse);
      expect(containsWord('99max said hi', 'max'), isFalse);
      expect(containsWord('max_99 said hi', 'max'), isFalse);
    });

    test('matches Cyrillic names bounded by punctuation or spaces', () {
      expect(containsWord('вера, привет', 'вера'), isTrue);
      expect(containsWord('привет вера', 'вера'), isTrue);
    });

    test('does not match inside a larger Cyrillic word', () {
      expect(containsWord('проверая текст', 'вера'), isFalse);
      expect(containsWord('вераника', 'вера'), isFalse);
    });

    test('treats adjacent CJK letters as word characters', () {
      expect(containsWord('小明你好', '小明'), isFalse);
      expect(containsWord('小明, 你好', '小明'), isTrue);
    });

    test('treats Greek and accented letters as word characters', () {
      expect(containsWord('γειά νίκος', 'νίκος'), isTrue);
      expect(containsWord('νίκοςα', 'νίκος'), isFalse);
      expect(containsWord('hey josé!', 'josé'), isTrue);
      expect(containsWord('joséphine', 'josé'), isFalse);
    });

    test('treats surrogate-pair letters as word characters', () {
      expect(containsWord('𝕒max', 'max'), isFalse);
      expect(containsWord('max𝕒', 'max'), isFalse);
    });

    test('treats emoji as boundaries', () {
      expect(containsWord('😀max😀', 'max'), isTrue);
    });

    test('returns false for an empty word', () {
      expect(containsWord('anything', ''), isFalse);
    });

    test('finds a bounded occurrence after an unbounded one', () {
      expect(containsWord('climax max', 'max'), isTrue);
    });
  });
}

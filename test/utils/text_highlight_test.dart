import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/text_highlight.dart';

void main() {
  group('highlightSpans', () {
    test('empty terms returns entire text as non-match', () {
      final spans = highlightSpans('hello world', []);
      expect(spans, hasLength(1));
      expect(spans[0].text, 'hello world');
      expect(spans[0].isMatch, isFalse);
    });

    test('single term matches correctly', () {
      final spans = highlightSpans('hello world', ['hello']);
      expect(spans, hasLength(2));
      expect(spans[0].text, 'hello');
      expect(spans[0].isMatch, isTrue);
      expect(spans[1].text, ' world');
      expect(spans[1].isMatch, isFalse);
    });

    test('multiple terms match independently', () {
      final spans = highlightSpans('run running ran', ['run', 'ran']);
      final matched = spans.where((s) => s.isMatch).map((s) => s.text).toList();
      expect(matched, containsAll(['run', 'ran']));
    });

    test('case-insensitive matching', () {
      final spans = highlightSpans('Hello HELLO hello', ['hello']);
      final matched = spans.where((s) => s.isMatch).toList();
      expect(matched, hasLength(3));
    });

    test('overlapping terms are merged', () {
      final spans = highlightSpans('abcde', ['abc', 'cde']);
      final matched = spans.where((s) => s.isMatch).toList();
      expect(matched, hasLength(1));
      expect(matched[0].text, 'abcde');
    });

    test('term not in text returns all as non-match', () {
      final spans = highlightSpans('hello world', ['xyz']);
      expect(spans, hasLength(1));
      expect(spans[0].isMatch, isFalse);
    });

    test('multiple occurrences of same term', () {
      final spans = highlightSpans('run and run again', ['run']);
      final matched = spans.where((s) => s.isMatch).toList();
      expect(matched, hasLength(2));
      expect(matched.every((s) => s.text == 'run'), isTrue);
    });

    test('empty text with terms returns single empty span', () {
      final spans = highlightSpans('', ['test']);
      expect(spans, isEmpty);
    });

    test('terms with empty strings are ignored', () {
      final spans = highlightSpans('hello', ['', 'hello']);
      final matched = spans.where((s) => s.isMatch).toList();
      expect(matched, hasLength(1));
    });
  });
}
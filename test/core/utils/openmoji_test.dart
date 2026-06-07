import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/openmoji.dart';

void main() {
  group('openMojiNameFor', () {
    test('simple single-codepoint emoji', () {
      expect(openMojiNameFor('\u{1F44D}'), '1F44D');
    });

    test('strips U+FE0F when the stripped form is the available asset', () {
      expect(openMojiNameFor('❤️'), '2764');
      expect(openMojiNameFor('❤'), '2764');
    });

    test('keeps U+FE0F for keycap sequences', () {
      expect(openMojiNameFor('#\u{FE0F}\u{20E3}'), '0023-FE0F-20E3');
    });

    test('regional indicator flag', () {
      expect(openMojiNameFor('\u{1F1FA}\u{1F1F8}'), '1F1FA-1F1F8');
    });

    test('skin-tone modifier', () {
      expect(openMojiNameFor('\u{1F44D}\u{1F3FF}'), '1F44D-1F3FF');
    });

    test('ZWJ sequence with skin tone', () {
      expect(
        openMojiNameFor('\u{1F469}\u{1F3FC}‍\u{1F9B2}'),
        '1F469-1F3FC-200D-1F9B2',
      );
    });

    test('non-emoji and unknown graphemes return null', () {
      expect(openMojiNameFor('a'), isNull);
      expect(openMojiNameFor(''), isNull);
      expect(openMojiNameFor('\u{10FFFD}'), isNull);
    });
  });

  group('openMojiAssetFor', () {
    test('returns bundled asset path for a known emoji', () {
      expect(openMojiAssetFor('\u{1F44D}'), 'assets/openmoji/1F44D.png');
      expect(openMojiAssetFor('❤️'), 'assets/openmoji/2764.png');
    });

    test('returns null for unknown grapheme', () {
      expect(openMojiAssetFor('x'), isNull);
    });
  });
}

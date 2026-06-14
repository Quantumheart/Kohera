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

  group('skin tones', () {
    test('applySkinTone inserts the modifier for a supporting emoji', () {
      expect(applySkinTone('\u{1F44D}', SkinTone.dark), '\u{1F44D}\u{1F3FF}');
      expect(
        openMojiNameFor(applySkinTone('\u{1F44D}', SkinTone.dark)),
        '1F44D-1F3FF',
      );
    });

    test('applySkinTone is a no-op for none', () {
      expect(applySkinTone('\u{1F44D}', SkinTone.none), '\u{1F44D}');
    });

    test('applySkinTone falls back when no toned variant exists', () {
      // Grinning face has no skin-tone variants.
      expect(applySkinTone('\u{1F600}', SkinTone.dark), '\u{1F600}');
    });

    test('openMojiSupportsSkinTone reflects availability', () {
      expect(openMojiSupportsSkinTone('\u{1F44D}'), isTrue);
      expect(openMojiSupportsSkinTone('\u{1F600}'), isFalse);
    });

    test('SkinTone.sample renders a toned hand', () {
      expect(SkinTone.dark.sample, '\u{270B}\u{1F3FF}');
      expect(SkinTone.none.sample, '\u{270B}');
    });
  });
}

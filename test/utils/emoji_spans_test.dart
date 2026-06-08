import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

void main() {
  const style = TextStyle(fontSize: 14);

  // A grapheme matched by the emoji regex but with no bundled OpenMoji asset,
  // so it exercises the font-fallback path.
  const unmappedEmoji = '\u{1FAFF}';

  group('buildEmojiSpans', () {
    test('plain text returns single span without emoji font fallback', () {
      final spans = buildEmojiSpans('hello world', style);
      expect(spans.length, 1);
      final span = spans.first as TextSpan;
      expect(span.text, 'hello world');
      expect(span.style?.fontFamilyFallback, isNull);
    });

    test('mapped emoji renders as an OpenMoji image span', () {
      final spans = buildEmojiSpans('😀', style);
      expect(spans.length, 1);
      expect(spans.first, isA<WidgetSpan>());
      final widgetSpan = spans.first as WidgetSpan;
      expect(widgetSpan.alignment, PlaceholderAlignment.middle);
      expect(widgetSpan.child, isA<OpenMojiImage>());
      final image = widgetSpan.child as OpenMojiImage;
      expect(image.size, isNotNull);
    });

    test('emoji image is sized to the surrounding line height', () {
      const styled = TextStyle(fontSize: 20, height: 1.5);
      final spans = buildEmojiSpans('😀', styled);
      final image = (spans.first as WidgetSpan).child as OpenMojiImage;
      expect(image.size, 20 * 1.5);
    });

    test('unmapped emoji falls back to font rendering', () {
      final spans = buildEmojiSpans(unmappedEmoji, style);
      expect(spans.length, 1);
      final span = spans.first as TextSpan;
      expect(span.text, unmappedEmoji);
      expect(span.style?.fontFamilyFallback, emojiFontFallback);
    });

    test('mixed text splits into text and emoji spans', () {
      final spans = buildEmojiSpans('hello 😀 world', style);
      expect(spans.length, 3);
      expect((spans[0] as TextSpan).text, 'hello ');
      expect((spans[0] as TextSpan).style?.fontFamilyFallback, isNull);
      expect(spans[1], isA<WidgetSpan>());
      expect((spans[2] as TextSpan).text, ' world');
      expect((spans[2] as TextSpan).style?.fontFamilyFallback, isNull);
    });

    test('consecutive emojis each become their own span', () {
      final spans = buildEmojiSpans('😀😎', style);
      expect(spans.length, 2);
      expect(spans[0], isA<WidgetSpan>());
      expect(spans[1], isA<WidgetSpan>());
    });

    test('null style is handled', () {
      final spans = buildEmojiSpans('hello 😀', null);
      expect(spans.length, 2);
      expect((spans[0] as TextSpan).text, 'hello ');
      expect((spans[0] as TextSpan).style, isNull);
      expect(spans[1], isA<WidgetSpan>());
    });

    test('empty string returns single span', () {
      final spans = buildEmojiSpans('', style);
      expect(spans.length, 1);
      expect((spans.first as TextSpan).text, '');
    });

    test('emoji at start of text', () {
      final spans = buildEmojiSpans('😀hello', style);
      expect(spans.length, 2);
      expect(spans[0], isA<WidgetSpan>());
      expect((spans[1] as TextSpan).text, 'hello');
    });

    test('emoji at end of text', () {
      final spans = buildEmojiSpans('hello😀', style);
      expect(spans.length, 2);
      expect((spans[0] as TextSpan).text, 'hello');
      expect(spans[1], isA<WidgetSpan>());
    });
  });

  group('isEmojiOnly', () {
    test('single emoji is emoji-only', () {
      expect(isEmojiOnly('😀'), isTrue);
    });

    test('multiple emoji separated by whitespace is emoji-only', () {
      expect(isEmojiOnly('😀 😎\t🎉'), isTrue);
    });

    test('surrounding whitespace is ignored', () {
      expect(isEmojiOnly('  😀  '), isTrue);
    });

    test('text mixed with emoji is not emoji-only', () {
      expect(isEmojiOnly('hi 😀'), isFalse);
    });

    test('plain text is not emoji-only', () {
      expect(isEmojiOnly('hello'), isFalse);
    });

    test('empty and whitespace-only are not emoji-only', () {
      expect(isEmojiOnly(''), isFalse);
      expect(isEmojiOnly('   '), isFalse);
    });
  });

  group('emojiFontFallback', () {
    test('contains expected font families', () {
      expect(emojiFontFallback, contains('Noto Color Emoji'));
      expect(emojiFontFallback, contains('Apple Color Emoji'));
      expect(emojiFontFallback, contains('Segoe UI Emoji'));
    });
  });
}

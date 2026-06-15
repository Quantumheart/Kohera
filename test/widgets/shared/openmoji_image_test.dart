import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// The [Text] glyph rendered inside an [OpenMojiImage].
Text _glyphOf(WidgetTester tester) => tester.widget<Text>(
      find.descendant(
        of: find.byType(OpenMojiImage),
        matching: find.byType(Text),
      ),
    );

void main() {
  testWidgets('renders the grapheme through the OpenMoji font', (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '\u{1F44D}', size: 24)),
    );

    final text = _glyphOf(tester);
    expect(text.data, '\u{1F44D}');
    expect(text.style?.fontFamily, openMojiFontFamily);
    expect(text.style?.fontSize, 24);
  });

  testWidgets('resolves an FE0F-stripped emoji through the font',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '❤️', size: 24)),
    );

    final text = _glyphOf(tester);
    expect(text.data, '❤️');
    expect(text.style?.fontFamily, openMojiFontFamily);
  });

  testWidgets('constrains the painted box to size', (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '\u{1F44D}', size: 24)),
    );

    expect(tester.getSize(find.byType(OpenMojiImage)), const Size(24, 24));
  });

  testWidgets('stays constrained when rendered inline in a WidgetSpan',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: OpenMojiImage(grapheme: '\u{1F44D}', size: 16),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(OpenMojiImage)), const Size(16, 16));
  });

  testWidgets('falls back to system-font text when not in the OpenMoji set',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: 'x', size: 24)),
    );

    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.fontFamily, isNot(openMojiFontFamily));
  });
}

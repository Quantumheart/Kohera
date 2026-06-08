import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/core/utils/openmoji_catalog.dart';
import 'package:kohera/features/chat/widgets/openmoji_picker.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

const _json = '''
{"groups":[
  {"key":"smileys-emotion","emoji":[
    {"e":"😀","n":"1F600","s":"grinning face happy"},
    {"e":"😢","n":"1F622","s":"crying face sad"},
    {"e":"👍","n":"1F44D","s":"thumbs up"}
  ]},
  {"key":"flags","emoji":[
    {"e":"🇺🇸","n":"1F1FA-1F1F8","s":"flag united states"}
  ]}
]}
''';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.payload);
  final String payload;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(payload)));
}

Finder _cell(String emoji) => find.byWidgetPredicate(
      (w) => w is OpenMojiImage && w.grapheme == emoji,
    );

Widget _wrap(
  void Function(String) onSelected, {
  SkinTone skinTone = SkinTone.none,
  ValueChanged<SkinTone>? onSkinToneChanged,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 350,
          height: 400,
          child: OpenMojiPicker(
            onSelected: onSelected,
            skinTone: skinTone,
            onSkinToneChanged: onSkinToneChanged,
          ),
        ),
      ),
    );

void main() {
  setUp(() async {
    OpenMojiCatalog.reset();
    await OpenMojiCatalog.load(_FakeBundle(_json));
  });

  testWidgets('renders the first category grid', (tester) async {
    await tester.pumpWidget(_wrap((_) {}));
    await tester.pump();

    expect(_cell('😀'), findsOneWidget);
    expect(_cell('😢'), findsOneWidget);
  });

  testWidgets('tapping an emoji selects its Unicode value', (tester) async {
    String? selected;
    await tester.pumpWidget(_wrap((e) => selected = e));
    await tester.pump();

    await tester.tap(_cell('😀'));
    expect(selected, '😀');
  });

  testWidgets('search filters across all categories', (tester) async {
    await tester.pumpWidget(_wrap((_) {}));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'united');
    await tester.pump();

    expect(_cell('🇺🇸'), findsOneWidget);
    expect(_cell('😀'), findsNothing);
  });

  testWidgets('applies the default skin tone to supporting emoji', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap((e) => selected = e, skinTone: SkinTone.dark),
    );
    await tester.pump();

    // 👍 gets the dark modifier; 😀 (no variant) is unchanged.
    expect(_cell('\u{1F44D}\u{1F3FF}'), findsOneWidget);
    expect(_cell('\u{1F44D}'), findsNothing);
    expect(_cell('😀'), findsOneWidget);

    await tester.tap(_cell('\u{1F44D}\u{1F3FF}'));
    expect(selected, '\u{1F44D}\u{1F3FF}');
  });

  testWidgets('shows the skin-tone selector only when onSkinToneChanged is set',
      (tester) async {
    await tester.pumpWidget(_wrap((_) {}));
    await tester.pump();
    expect(find.byTooltip('Default skin tone'), findsNothing);

    await tester.pumpWidget(_wrap((_) {}, onSkinToneChanged: (_) {}));
    await tester.pump();
    expect(find.byTooltip('Default skin tone'), findsOneWidget);
  });

  testWidgets('header swatch opens the default-tone strip and sets the tone',
      (tester) async {
    SkinTone? chosen;
    await tester.pumpWidget(_wrap((_) {}, onSkinToneChanged: (t) => chosen = t));
    await tester.pump();

    await tester.tap(find.byTooltip('Default skin tone'));
    await tester.pump();

    // The strip shows toned sample hands; tap the dark one.
    await tester.tap(_cell(SkinTone.dark.sample));
    expect(chosen, SkinTone.dark);
  });

  testWidgets('long-press opens a per-emoji tone override', (tester) async {
    String? selected;
    await tester.pumpWidget(_wrap((e) => selected = e));
    await tester.pump();

    await tester.longPress(_cell('👍'));
    await tester.pump();

    // Strip shows toned variants; the dark one only exists in the strip.
    await tester.tap(_cell('\u{1F44D}\u{1F3FF}'));
    expect(selected, '\u{1F44D}\u{1F3FF}');
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/openmoji_catalog.dart';
import 'package:kohera/features/chat/widgets/openmoji_picker.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

const _json = '''
{"groups":[
  {"key":"smileys-emotion","emoji":[
    {"e":"😀","n":"1F600","s":"grinning face happy"},
    {"e":"😢","n":"1F622","s":"crying face sad"}
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

Widget _wrap(void Function(String) onSelected) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 350,
          height: 400,
          child: OpenMojiPicker(onSelected: onSelected),
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
}

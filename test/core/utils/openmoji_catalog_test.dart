import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/openmoji_catalog.dart';

const _json = '''
{"groups":[
  {"key":"smileys-emotion","emoji":[
    {"e":"😀","n":"1F600","s":"grinning face happy smile"},
    {"e":"😢","n":"1F622","s":"crying face sad tear"}
  ]},
  {"key":"flags","emoji":[
    {"e":"🇺🇸","n":"1F1FA-1F1F8","s":"flag united states america"}
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

void main() {
  setUp(OpenMojiCatalog.reset);

  test('loads grouped categories in order', () async {
    final categories = await OpenMojiCatalog.load(_FakeBundle(_json));
    expect(categories.map((c) => c.key), ['smileys-emotion', 'flags']);
    expect(categories.first.emoji.length, 2);
    expect(categories.first.emoji.first.emoji, '😀');
    expect(categories.first.emoji.first.asset, 'assets/openmoji/1F600.png');
  });

  test('all flattens every category', () async {
    await OpenMojiCatalog.load(_FakeBundle(_json));
    expect(OpenMojiCatalog.all.length, 3);
  });

  test('search matches all whitespace-separated terms', () async {
    await OpenMojiCatalog.load(_FakeBundle(_json));
    expect(OpenMojiCatalog.search('grinning').single.emoji, '😀');
    expect(OpenMojiCatalog.search('united states').single.emoji, '🇺🇸');
    expect(OpenMojiCatalog.search('happy sad'), isEmpty);
    expect(OpenMojiCatalog.search(''), isEmpty);
  });

  test('load result is cached across calls', () async {
    final first = await OpenMojiCatalog.load(_FakeBundle(_json));
    final second = await OpenMojiCatalog.load(_FakeBundle('{"groups":[]}'));
    expect(identical(first, second), isTrue);
  });
}

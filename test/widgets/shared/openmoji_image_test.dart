import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// Asset name behind an [Image], unwrapping the [ResizeImage] that `cacheWidth`
/// introduces.
String _assetOf(Image image) {
  final provider = image.image;
  final asset =
      provider is ResizeImage ? provider.imageProvider : provider;
  return (asset as AssetImage).assetName;
}

void main() {
  testWidgets('renders the OpenMoji asset for a bundled emoji', (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '\u{1F44D}', size: 24)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(_assetOf(image), 'assets/openmoji/1F44D.png');
    expect(image.width, 24);
    expect(image.height, 24);
  });

  testWidgets('strips FE0F to resolve the asset', (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '❤️', size: 24)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(_assetOf(image), 'assets/openmoji/2764.png');
  });

  testWidgets('falls back to text when no asset is bundled', (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: 'x', size: 24)),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('x'), findsOneWidget);
  });
}

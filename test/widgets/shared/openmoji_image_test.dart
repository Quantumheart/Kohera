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

  testWidgets('decodes at a fixed pixel grid with nearest-neighbour painting',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '\u{1F44D}', size: 16)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    // Fixed 32px decode grid → crisp blocks when scaled, independent of DPR.
    expect(provider.width, 32);
    expect(provider.height, 32);
    expect(image.filterQuality, FilterQuality.none);
  });

  testWidgets('uses the same pixel grid regardless of paint size',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: '\u{1F44D}', size: 64)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    // Larger paints upscale the same 32px grid → chunky pixels.
    expect(provider.width, 32);
    expect(provider.height, 32);
    expect(image.filterQuality, FilterQuality.none);
  });

  testWidgets('falls back to text when no asset is bundled', (tester) async {
    await tester.pumpWidget(
      _wrap(const OpenMojiImage(grapheme: 'x', size: 24)),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('precacheOpenMoji bails out on a deactivated context',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(_wrap(Builder(
      builder: (ctx) {
        captured = ctx;
        return const SizedBox();
      },
    ),),);

    // Tear the owning element out of the tree so its context deactivates,
    // mirroring a HoverActionBar disposed mid-precache.
    await tester.pumpWidget(_wrap(const SizedBox()));

    // Without the context.mounted guard this throws "Looking up a deactivated
    // widget's ancestor is unsafe" from precacheImage.
    await precacheOpenMoji(captured, const ['\u{1F44D}']);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/data/openmoji_catalog.dart';

void main() {
  group('kOpenMojiCatalog', () {
    test('is not empty and every pack has emoji', () {
      expect(kOpenMojiCatalog, isNotEmpty);
      for (final pack in kOpenMojiCatalog) {
        expect(pack.emojis, isNotEmpty, reason: '${pack.id} has no emoji');
        expect(pack.amount, pack.emojis.length);
      }
    });

    test('pack ids are unique', () {
      final ids = kOpenMojiCatalog.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('hexcodes are uppercase hex segments', () {
      final hexSegment = RegExp(r'^[0-9A-F]+(-[0-9A-F]+)*$');
      for (final pack in kOpenMojiCatalog) {
        for (final emoji in pack.emojis) {
          expect(
            hexSegment.hasMatch(emoji.hexcode),
            isTrue,
            reason: 'invalid hexcode ${emoji.hexcode} in ${pack.id}',
          );
        }
      }
    });

    test('shortcodes are unique within each pack', () {
      for (final pack in kOpenMojiCatalog) {
        final codes = pack.emojis.map((e) => e.shortcode).toList();
        expect(
          codes.toSet().length,
          codes.length,
          reason: 'duplicate shortcode in ${pack.id}',
        );
      }
    });

    test('builds the openmoji.org image URL from the hexcode', () {
      final emoji = kOpenMojiCatalog.first.emojis.first;
      expect(
        emoji.imageUrl('https://openmoji.org/data/color/72x72'),
        'https://openmoji.org/data/color/72x72/${emoji.hexcode}.png',
      );
    });
  });
}

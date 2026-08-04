import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/emoji_gg_pack.dart';

void main() {
  group('EmojiGgEmoji', () {
    test('imageUrl uses CDN with slug', () {
      const emoji = EmojiGgEmoji(slug: '4384_falco_stare', title: 'falco stare');
      expect(
        emoji.imageUrl,
        'https://cdn3.emoji.gg/emojis/4384_falco_stare.png',
      );
    });

    test('shortcode strips numeric ID prefix with underscore', () {
      const emoji = EmojiGgEmoji(slug: '4384_falco_stare', title: 'falco stare');
      expect(emoji.shortcode, 'falco_stare');
    });

    test('shortcode strips numeric ID prefix with hyphen', () {
      const emoji = EmojiGgEmoji(slug: '664414-name', title: 'name');
      expect(emoji.shortcode, 'name');
    });

    test('shortcode with no numeric prefix is unchanged', () {
      const emoji = EmojiGgEmoji(slug: 'plain_slug', title: 'plain slug');
      expect(emoji.shortcode, 'plain_slug');
    });
  });

  group('EmojiGgPack.fromJson', () {
    test('parses a well-formed pack', () {
      final pack = EmojiGgPack.fromJson({
        'id': 42,
        'name': 'Falco Pack',
        'slug': 'falco-pack',
        'description': 'A pack of Falco emojis',
        'amount': 5,
        'emojis': '4384_falco_stare.png,664414-falco_wink.png',
        'category': 'gaming',
      });

      expect(pack, isNotNull);
      expect(pack!.id, 42);
      expect(pack.name, 'Falco Pack');
      expect(pack.slug, 'falco-pack');
      expect(pack.description, 'A pack of Falco emojis');
      expect(pack.amount, 5);
      expect(pack.emojiSlugs, ['4384_falco_stare', '664414-falco_wink']);
      expect(pack.category, 'gaming');
    });

    test('emojis getter builds EmojiGgEmoji list with titles', () {
      final pack = EmojiGgPack.fromJson({
        'id': 1,
        'name': 'Test',
        'slug': 'test',
        'description': '',
        'amount': 2,
        'emojis': '4384_falco_stare,664414-falco_wink',
      })!;

      final emojis = pack.emojis;
      expect(emojis.length, 2);
      expect(emojis[0].slug, '4384_falco_stare');
      expect(emojis[0].title, 'falco stare');
      expect(emojis[1].slug, '664414-falco_wink');
      expect(emojis[1].title, 'falco wink');
    });

    test('returns null when id is missing', () {
      expect(EmojiGgPack.fromJson({'name': 'No ID'}), isNull);
    });

    test('defaults name/slug/description to empty strings', () {
      final pack = EmojiGgPack.fromJson({'id': 7, 'emojis': ''})!;

      expect(pack.name, '');
      expect(pack.slug, '');
      expect(pack.description, '');
    });

    test('defaults amount to slug count when amount missing', () {
      final pack = EmojiGgPack.fromJson({
        'id': 9,
        'emojis': 'a_slug,b_slug,c_slug',
      })!;

      expect(pack.amount, 3);
    });

    test('handles empty emojis string as empty list', () {
      final pack = EmojiGgPack.fromJson({'id': 1, 'emojis': ''})!;

      expect(pack.emojiSlugs, isEmpty);
      expect(pack.emojis, isEmpty);
    });

    test('handles missing emojis field as empty list', () {
      final pack = EmojiGgPack.fromJson({'id': 1})!;

      expect(pack.emojiSlugs, isEmpty);
    });

    test('trims whitespace and strips .png suffix from slugs', () {
      final pack = EmojiGgPack.fromJson({
        'id': 1,
        'emojis': '  slug_one.png , slug_two.png ,',
      })!;

      expect(pack.emojiSlugs, ['slug_one', 'slug_two']);
    });

    test('filters out empty slug entries', () {
      final pack = EmojiGgPack.fromJson({
        'id': 1,
        'emojis': 'good_one,,,  ,good_two',
      })!;

      expect(pack.emojiSlugs, ['good_one', 'good_two']);
    });

    test('category defaults to null', () {
      final pack = EmojiGgPack.fromJson({'id': 1, 'emojis': ''})!;

      expect(pack.category, isNull);
    });

    test('returns null on type mismatch (id is String)', () {
      expect(
        EmojiGgPack.fromJson({
          'id': 'not-an-int',
          'emojis': '',
        }),
        isNull,
      );
    });
  });
}
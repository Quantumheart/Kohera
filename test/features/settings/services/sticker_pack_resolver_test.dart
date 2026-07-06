import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/shared/services/sticker_pack_resolver.dart';

void main() {
  group('StickerPackResolver', () {
    final source = StickerPack(
      id: 'im.ponies.user_emotes',
      displayName: 'My Emotes',
      avatarUrl: Uri.parse('mxc://example.com/avatar123'),
      stickers: [
        PackImage(
          shortcode: 'wave',
          url: Uri.parse('mxc://example.com/wave'),
          body: 'Wave sticker',
          isSticker: true,
          isEmoji: false,
          width: 256,
          height: 256,
        ),
      ],
      emoji: [
        PackImage(
          shortcode: 'smile',
          url: Uri.parse('mxc://example.com/smile'),
          body: 'Smile emoji',
          isSticker: false,
          isEmoji: true,
        ),
      ],
    );

    test('maps id, name (=id), displayName', () {
      final kohera = const StickerPackResolver()(source, isInstalled: true);
      expect(kohera.id, 'im.ponies.user_emotes');
      expect(kohera.name, 'im.ponies.user_emotes');
      expect(kohera.displayName, 'My Emotes');
    });

    test('converts avatarUrl Uri to iconUrl string', () {
      final kohera = const StickerPackResolver()(source, isInstalled: true);
      expect(kohera.iconUrl, 'mxc://example.com/avatar123');
    });

    test('iconUrl is null when source has no avatar', () {
      const noAvatar = StickerPack(
        id: 'p',
        displayName: 'No Avatar',
        stickers: [],
        emoji: [],
      );
      expect(
        const StickerPackResolver()(noAvatar, isInstalled: true).iconUrl,
        isNull,
      );
    });

    test('sets isInstalled from the parameter', () {
      expect(
        const StickerPackResolver()(source, isInstalled: true).isInstalled,
        isTrue,
      );
      expect(
        const StickerPackResolver()(source, isInstalled: false).isInstalled,
        isFalse,
      );
    });

    test('maps stickers and emoji to KoheraSticker with url string + dims', () {
      final kohera = const StickerPackResolver()(source, isInstalled: true);
      expect(kohera.stickers, hasLength(1));
      expect(kohera.stickers.first.shortCode, 'wave');
      expect(kohera.stickers.first.mxcUrl, 'mxc://example.com/wave');
      expect(kohera.stickers.first.width, 256);
      expect(kohera.stickers.first.height, 256);

      expect(kohera.emoji, hasLength(1));
      expect(kohera.emoji.first.shortCode, 'smile');
      expect(kohera.emoji.first.mxcUrl, 'mxc://example.com/smile');
      expect(kohera.emoji.first.width, isNull);
      expect(kohera.emoji.first.height, isNull);
    });

    test('preserves counts used by the settings subtitle', () {
      final kohera = const StickerPackResolver()(source, isInstalled: true);
      expect(kohera.stickerCount, 1);
      expect(kohera.emojiCount, 1);
      expect(kohera.isEmpty, isFalse);
    });
  });

  group('StickerPack.fromContent dimension extraction', () {
    test('extracts width/height from image info', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: {
          'pack': {'display_name': 'Dim Pack'},
          'images': {
            'big': {
              'url': 'mxc://example.com/big',
              'info': {'w': 512, 'h': 384},
            },
            'small': {
              'url': 'mxc://example.com/small',
            },
          },
        },
      )!;

      final big = pack.allImages.firstWhere((i) => i.shortcode == 'big');
      expect(big.width, 512);
      expect(big.height, 384);

      final small = pack.allImages.firstWhere((i) => i.shortcode == 'small');
      expect(small.width, isNull);
      expect(small.height, isNull);
    });

    test('coerces numeric (non-int) dimension values to int', () {
      final pack = StickerPack.fromContent(
        id: 'test',
        content: {
          'pack': {'display_name': 'Num Pack'},
          'images': {
            'x': {
              'url': 'mxc://example.com/x',
              'info': {'w': 200.0, 'h': 100.5},
            },
          },
        },
      )!;
      final img = pack.stickers.first;
      expect(img.width, 200);
      expect(img.height, 100);
    });
  });
}

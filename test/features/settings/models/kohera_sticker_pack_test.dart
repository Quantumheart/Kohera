import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/models/kohera_sticker_pack.dart';

void main() {
  group('KoheraSticker', () {
    test('stores shortcode, mxcUrl and optional dimensions', () {
      const sticker = KoheraSticker(shortCode: 'wave', mxcUrl: 'mxc://x/wave');
      expect(sticker.shortCode, 'wave');
      expect(sticker.mxcUrl, 'mxc://x/wave');
      expect(sticker.width, isNull);
      expect(sticker.height, isNull);
      expect(sticker.altText, ':wave:');
    });

    test('carries native dimensions when provided', () {
      const sticker = KoheraSticker(
        shortCode: 'blob',
        mxcUrl: 'mxc://x/blob',
        width: 256,
        height: 256,
      );
      expect(sticker.width, 256);
      expect(sticker.height, 256);
    });
  });

  group('KoheraStickerPack', () {
    const pack = KoheraStickerPack(
      id: 'im.ponies.user_emotes',
      name: 'im.ponies.user_emotes',
      displayName: 'My Pack',
      iconUrl: 'mxc://example.com/avatar',
      isInstalled: true,
      stickers: [
        KoheraSticker(shortCode: 'wave', mxcUrl: 'mxc://x/wave'),
        KoheraSticker(shortCode: 'party', mxcUrl: 'mxc://x/party'),
      ],
      emoji: [KoheraSticker(shortCode: 'smile', mxcUrl: 'mxc://x/smile')],
    );

    test('exposes sticker/emoji counts', () {
      expect(pack.stickerCount, 2);
      expect(pack.emojiCount, 1);
    });

    test('isEmpty is false when any image is present', () {
      expect(pack.isEmpty, isFalse);
    });

    test('isEmpty is true for an empty pack', () {
      const empty = KoheraStickerPack(
        id: 'empty',
        name: 'empty',
        displayName: 'Empty',
        iconUrl: null,
        isInstalled: false,
        stickers: [],
        emoji: [],
      );
      expect(empty.isEmpty, isTrue);
    });

    test('isInstalled flag is preserved', () {
      expect(pack.isInstalled, isTrue);
      const available = KoheraStickerPack(
        id: '!room:example.com',
        name: '!room:example.com',
        displayName: 'Room Pack',
        iconUrl: null,
        isInstalled: false,
        stickers: [],
        emoji: [],
      );
      expect(available.isInstalled, isFalse);
    });
  });
}

import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/shared/models/kohera_sticker_pack.dart';

/// Converts an SDK-coupled [StickerPack] into a UI-ready, SDK-free
/// [KoheraStickerPack].
///
/// This resolver is the conversion boundary: it is the only place that imports
/// both the SDK-coupled `StickerPack` and the SDK-free `KoheraStickerPack`.
/// [StickerPackService] calls it internally and exposes only `KoheraStickerPack`
/// to the sticker settings screen, so the screen never touches a Matrix SDK
/// type. Invoke as `const StickerPackResolver()(pack, isInstalled: true)`.
///
/// [isInstalled] is supplied by the service depending on the pack's source:
/// `true` for account packs (personal/imported/subscribed) and the built-in
/// OpenMoji pack, `false` for packs merely available from joined rooms.
class StickerPackResolver {
  const StickerPackResolver();

  KoheraStickerPack call(StickerPack pack, {required bool isInstalled}) {
    return KoheraStickerPack(
      id: pack.id,
      name: pack.id,
      displayName: pack.displayName,
      iconUrl: pack.avatarUrl?.toString(),
      isInstalled: isInstalled,
      stickers: pack.stickers.map(_toKoheraSticker).toList(),
      emoji: pack.emoji.map(_toKoheraSticker).toList(),
    );
  }

  KoheraSticker _toKoheraSticker(PackImage img) => KoheraSticker(
        shortCode: img.shortcode,
        mxcUrl: img.url.toString(),
        width: img.width,
        height: img.height,
      );
}

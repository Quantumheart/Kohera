/// A single image entry within a sticker/emoji pack.
///
/// SDK-free representation of a pack image. The [mxcUrl] is the raw `mxc://`
/// URI as a string; [width]/[height] are the native image dimensions when
/// available from the source pack content (otherwise `null`).
class KoheraSticker {
  const KoheraSticker({
    required this.shortCode,
    required this.mxcUrl,
    this.width,
    this.height,
  });

  /// The shortcode (without surrounding colons), e.g. `wave`.
  final String shortCode;

  /// The `mxc://` (or `openmoji://` for built-in) media URI as a string.
  final String mxcUrl;

  /// Native image width in pixels, or `null` when the source has no `info`.
  final int? width;

  /// Native image height in pixels, or `null` when the source has no `info`.
  final int? height;

  String get altText => ':$shortCode:';
}

/// A resolved, UI-ready sticker/emoji pack with no Matrix SDK dependency.
///
/// This is the Kohera-owned domain model consumed by the sticker settings
/// screen. Conversion from the SDK-coupled [StickerPack] (which imports
/// `package:matrix/matrix.dart`) happens inside [StickerPackService] via
/// [toKoheraStickerPack] — the screen only ever sees this SDK-free type.
class KoheraStickerPack {
  const KoheraStickerPack({
    required this.id,
    required this.name,
    required this.displayName,
    required this.iconUrl,
    required this.isInstalled,
    required this.stickers,
    required this.emoji,
  });

  /// Stable identifier. For the user's own pack: `im.ponies.user_emotes`.
  /// For room/space packs: the room id. For emoji.gg imports: `emojigg_<id>`.
  /// For the built-in pack: `openmoji_builtin`.
  final String id;

  /// The machine/identifier name of the pack. Today this mirrors [id]; it is
  /// reserved for the MSC2545 state-key distinction if pack sourcing is
  /// generalized later (packs may share a room but differ by state key).
  final String name;

  /// Human-readable display name shown in the UI.
  final String displayName;

  /// The pack icon `mxc://` URI as a string, or `null` when the pack has no
  /// avatar. Already filtered to `mxc` scheme at the conversion boundary.
  final String? iconUrl;

  /// Whether the pack is installed/subscribed for the current account.
  /// `true` for account packs (personal/imported/subscribed) and the built-in
  /// OpenMoji pack; `false` for packs merely available from joined rooms.
  final bool isInstalled;

  /// Sticker images in the pack (rendered at a larger size).
  final List<KoheraSticker> stickers;

  /// Emoji images in the pack (rendered inline at a smaller size).
  ///
  /// This list is beyond the issue #709 literal field spec, which lists only
  /// `stickers`. It is included because the sticker settings screen renders a
  /// subtitle of "X stickers, Y emoji" from `stickers.length`/`emoji.length`,
  /// and changing the management UI is explicitly out of scope. Each entry is
  /// the same [KoheraSticker] shape; no SDK type is involved.
  final List<KoheraSticker> emoji;

  bool get isEmpty => stickers.isEmpty && emoji.isEmpty;
  int get stickerCount => stickers.length;
  int get emojiCount => emoji.length;
}

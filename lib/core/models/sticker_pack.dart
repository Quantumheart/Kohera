import 'package:matrix/matrix.dart';

/// A single image entry within a sticker/emoji pack.
class PackImage {
  const PackImage({
    required this.shortcode,
    required this.url,
    required this.isSticker,
    required this.isEmoji,
    this.body,
    this.emoji,
  });

  final String shortcode;
  final Uri url;
  final bool isSticker;
  final bool isEmoji;
  final String? body;

  /// The Unicode emoji grapheme for built-in OpenMoji entries. When non-null
  /// the image renders as a local OpenMoji asset and inserts this grapheme;
  /// when null it is a remote (mxc/http) custom emoji.
  final String? emoji;

  String get altText => body ?? ':$shortcode:';
}

/// A resolved, UI-ready sticker/emoji pack.
class StickerPack {
  const StickerPack({
    required this.id,
    required this.displayName,
    required this.stickers,
    required this.emoji,
    this.avatarUrl,
  });

  /// Stable identifier. For the user's own pack: `im.ponies.user_emotes`.
  /// For room/space packs: the room ID.
  final String id;
  final String displayName;
  final Uri? avatarUrl;
  final List<PackImage> stickers;
  final List<PackImage> emoji;

  bool get isEmpty => stickers.isEmpty && emoji.isEmpty;

  List<PackImage> get allImages => [...stickers, ...emoji];

  /// Parses an MSC2545 image pack content map into a [StickerPack].
  /// Returns null if the content has no usable images.
  static StickerPack? fromContent({
    required String id,
    required Map<String, Object?> content,
  }) {
    final pack = ImagePackContent.fromJson(content);
    if (pack.images.isEmpty) return null;

    final defaultUsage = pack.pack.usage;
    final defaultIsSticker =
        defaultUsage == null || defaultUsage.contains(ImagePackUsage.sticker);
    final defaultIsEmoji =
        defaultUsage == null || defaultUsage.contains(ImagePackUsage.emoticon);

    final stickers = <PackImage>[];
    final emoji = <PackImage>[];

    for (final entry in pack.images.entries) {
      final imgUsage = entry.value.usage;
      final isSticker = imgUsage != null
          ? imgUsage.contains(ImagePackUsage.sticker)
          : defaultIsSticker;
      final isEmoji = imgUsage != null
          ? imgUsage.contains(ImagePackUsage.emoticon)
          : defaultIsEmoji;

      if (!isSticker && !isEmoji) continue;

      final image = PackImage(
        shortcode: entry.key,
        url: entry.value.url,
        body: entry.value.body,
        isSticker: isSticker,
        isEmoji: isEmoji,
      );
      if (isSticker) stickers.add(image);
      if (isEmoji) emoji.add(image);
    }

    if (stickers.isEmpty && emoji.isEmpty) return null;

    // The SDK defaults avatarUrl to Uri.parse('.::'). Only keep mxc:// URIs.
    final rawAvatar = pack.pack.avatarUrl;
    final avatarUrl =
        (rawAvatar != null && rawAvatar.scheme == 'mxc') ? rawAvatar : null;

    return StickerPack(
      id: id,
      displayName: pack.pack.displayName ?? id,
      avatarUrl: avatarUrl,
      stickers: stickers,
      emoji: emoji,
    );
  }
}

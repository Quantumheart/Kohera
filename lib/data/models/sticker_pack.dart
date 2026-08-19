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
    this.width,
    this.height,
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

  /// Native image width in pixels, or `null` when the source pack content
  /// carries no `info.w`. Extracted from the MSC2545 image `info` map.
  final int? width;

  /// Native image height in pixels, or `null` when the source pack content
  /// carries no `info.h`. Extracted from the MSC2545 image `info` map.
  final int? height;

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

      // Extract native dimensions from the MSC2545 image `info` map.
      final info = entry.value.info;
      final width = info == null ? null : _toInt(info['w']);
      final height = info == null ? null : _toInt(info['h']);

      final image = PackImage(
        shortcode: entry.key,
        url: entry.value.url,
        body: entry.value.body,
        isSticker: isSticker,
        isEmoji: isEmoji,
        width: width,
        height: height,
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

  /// Safely coerces an MSC2545 `info` dimension value to [int].
  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

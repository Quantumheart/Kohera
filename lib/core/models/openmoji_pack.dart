/// A single OpenMoji emoji, identified by its Unicode hexcode.
///
/// Image assets are served by openmoji.org under
/// `https://openmoji.org/data/color/72x72/<hexcode>.png`.
class OpenMojiEmoji {
  const OpenMojiEmoji({
    required this.hexcode,
    required this.shortcode,
    required this.annotation,
  });

  /// Uppercase Unicode codepoint(s), `-` separated (e.g. `1F600`).
  final String hexcode;

  /// Shortcode used in `:shortcode:` autocomplete and account-data storage.
  final String shortcode;

  /// Human-readable name shown as the image body / alt text.
  final String annotation;

  String imageUrl(String baseUrl) => '$baseUrl/$hexcode.png';
}

/// A curated default emoji pack sourced from OpenMoji (https://openmoji.org/),
/// the open-source emoji project licensed under CC BY-SA 4.0.
class OpenMojiPack {
  const OpenMojiPack({
    required this.id,
    required this.name,
    required this.description,
    required this.emojis,
  });

  /// Stable identifier, also used as the imported pack's `source_slug`.
  final String id;
  final String name;
  final String description;
  final List<OpenMojiEmoji> emojis;

  int get amount => emojis.length;
}

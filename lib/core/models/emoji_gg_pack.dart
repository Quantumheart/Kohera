class EmojiGgEmoji {
  const EmojiGgEmoji({required this.slug, required this.title});

  final String slug;
  final String title;

  String get imageUrl => 'https://cdn3.emoji.gg/emojis/$slug.png';

  /// Strips the numeric ID prefix: "4384_falco_stare" → "falco_stare".
  String get shortcode => slug.replaceFirst(RegExp(r'^\d+_'), '');
}

class EmojiGgPack {
  const EmojiGgPack({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.amount,
    required this.emojiSlugs,
    this.category,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final int amount;

  /// Slugs parsed from the comma-separated `emojis` field.
  final List<String> emojiSlugs;
  final String? category;

  List<EmojiGgEmoji> get emojis => emojiSlugs
      .map(
        (s) => EmojiGgEmoji(
          slug: s,
          title: s
              .replaceFirst(RegExp(r'^\d+_'), '')
              .replaceAll('_', ' '),
        ),
      )
      .toList();

  static EmojiGgPack? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      if (id == null) return null;

      final slugsRaw = (json['emojis'] as String?) ?? '';
      final slugs = slugsRaw.isEmpty
          ? <String>[]
          : slugsRaw
              .split(',')
              .map((s) => s.trim().replaceAll(RegExp(r'\.png$'), ''))
              .where((s) => s.isNotEmpty)
              .toList();

      return EmojiGgPack(
        id: id as int,
        name: (json['name'] as String?) ?? '',
        slug: (json['slug'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        amount: (json['amount'] as int?) ?? slugs.length,
        emojiSlugs: slugs,
        category: json['category'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

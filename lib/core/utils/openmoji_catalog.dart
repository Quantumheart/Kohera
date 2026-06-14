import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single emoji entry from the OpenMoji metadata.
class OpenMojiEmoji {
  const OpenMojiEmoji({
    required this.emoji,
    required this.name,
    required this.annotation,
    required this.search,
  });

  /// The Unicode emoji string (inserted/applied on selection).
  final String emoji;

  /// The OpenMoji asset base name (codepoint sequence, no extension).
  final String name;

  /// Human-readable name (e.g. "grinning face").
  final String annotation;

  /// Lowercased annotation + tags, used for search matching.
  final String search;

  /// `:shortcode:`-style identifier derived from [annotation]
  /// (e.g. "grinning_face").
  String get shortcode => annotation
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

/// A named group of emoji (e.g. smileys-emotion, flags).
class OpenMojiCategory {
  const OpenMojiCategory({required this.key, required this.emoji});

  final String key;
  final List<OpenMojiEmoji> emoji;
}

/// Loads and caches the bundled OpenMoji picker metadata.
class OpenMojiCatalog {
  OpenMojiCatalog._();

  static const _assetPath = 'assets/openmoji/metadata.json';

  static List<OpenMojiCategory>? _categories;
  static Future<List<OpenMojiCategory>>? _loading;

  /// All categories in picker display order. Loaded once and cached.
  static Future<List<OpenMojiCategory>> load([AssetBundle? bundle]) {
    if (_categories != null) return Future.value(_categories);
    return _loading ??= _read(bundle ?? rootBundle);
  }

  @visibleForTesting
  static void reset() {
    _categories = null;
    _loading = null;
  }

  static Future<List<OpenMojiCategory>> _read(AssetBundle bundle) async {
    final raw = await bundle.loadString(_assetPath);
    final json = jsonDecode(raw) as Map<String, Object?>;
    final groups = (json['groups']! as List)
        .map((g) => g! as Map<String, Object?>)
        .map(
          (g) => OpenMojiCategory(
            key: g['key']! as String,
            emoji: (g['emoji']! as List)
                .map((e) => e! as Map<String, Object?>)
                .map(
                  (e) => OpenMojiEmoji(
                    emoji: e['e']! as String,
                    name: e['n']! as String,
                    annotation: (e['a'] as String?) ?? '',
                    search: e['s']! as String,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    _categories = groups;
    _loading = null;
    return groups;
  }

  /// Flat list of every emoji across all categories.
  static List<OpenMojiEmoji> get all =>
      [for (final c in _categories ?? const <OpenMojiCategory>[]) ...c.emoji];

  /// Emoji whose search text contains every whitespace-separated term in
  /// [query]. Returns an empty list before [load] completes.
  static List<OpenMojiEmoji> search(String query) {
    final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (terms.isEmpty) return const [];
    return all
        .where((e) => terms.every((t) => e.search.contains(t)))
        .toList(growable: false);
  }
}

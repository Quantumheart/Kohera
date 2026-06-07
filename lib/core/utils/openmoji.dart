import 'package:kohera/core/utils/openmoji_manifest.g.dart';

const _openMojiAssetDir = 'assets/openmoji';

const _variationSelectors = {0xFE0E, 0xFE0F};

/// Codepoint sequence base name for [grapheme] following OpenMoji's filename
/// convention: uppercase hex codepoints joined by `-`.
String _name(Iterable<int> codepoints) => codepoints
    .map((c) => c.toRadixString(16).toUpperCase().padLeft(4, '0'))
    .join('-');

/// Resolves the OpenMoji asset base name (no extension) for a single emoji
/// [grapheme], or `null` when no matching asset exists.
///
/// OpenMoji is inconsistent about variation selectors — keycaps keep `U+FE0F`
/// (`0023-FE0F-20E3`) while most others drop it (`2764`). So we try the literal
/// sequence first, then the sequence with variation selectors removed.
String? openMojiNameFor(String grapheme) {
  final runes = grapheme.runes.toList();
  if (runes.isEmpty) return null;

  final asIs = _name(runes);
  if (kOpenMojiNames.contains(asIs)) return asIs;

  final stripped = _name(runes.where((c) => !_variationSelectors.contains(c)));
  if (stripped != asIs && kOpenMojiNames.contains(stripped)) return stripped;

  return null;
}

/// Resolves the bundled OpenMoji asset path for a single emoji [grapheme], or
/// `null` when no matching asset exists (caller should fall back to text).
String? openMojiAssetFor(String grapheme) {
  final name = openMojiNameFor(grapheme);
  return name == null ? null : '$_openMojiAssetDir/$name.png';
}

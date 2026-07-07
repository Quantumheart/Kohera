import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/core/utils/openmoji_catalog.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';
// ── OpenMojiPicker ───────────────────────────────────────────

/// In-house emoji picker rendering OpenMoji image assets in a tabbed,
/// searchable grid. Calls [onSelected] with the Unicode emoji on tap.
///
/// Tone-supporting emoji render with [skinTone] applied; long-pressing one
/// opens an inline tone strip to insert a per-emoji override. When
/// [onSkinToneChanged] is provided a header swatch opens the same strip for
/// changing the default tone.
class OpenMojiPicker extends StatefulWidget {
  const OpenMojiPicker({
    required this.onSelected,
    super.key,
    this.columns = 8,
    this.skinTone = SkinTone.none,
    this.onSkinToneChanged,
  });

  final void Function(String emoji) onSelected;
  final int columns;
  final SkinTone skinTone;
  final ValueChanged<SkinTone>? onSkinToneChanged;

  @override
  State<OpenMojiPicker> createState() => _OpenMojiPickerState();
}

class _OpenMojiPickerState extends State<OpenMojiPicker> {
  static const _icons = <String, IconData>{
    'smileys-emotion': KIcons.emojiEmotionsOutlined,
    'people-body': KIcons.emojiPeopleOutlined,
    'animals-nature': KIcons.petsOutlined,
    'food-drink': KIcons.fastfoodOutlined,
    'travel-places': KIcons.directionsCarOutlined,
    'activities': KIcons.sportsBasketballOutlined,
    'objects': KIcons.lightbulbOutline,
    'symbols': KIcons.emojiSymbolsOutlined,
    'flags': KIcons.flagOutlined,
  };

  List<OpenMojiCategory>? _categories;
  String _query = '';

  /// When non-null, the inline tone strip is open. An empty string means the
  /// header (default-tone) strip; otherwise the per-emoji override for that
  /// base grapheme.
  String? _toneStripBase;

  @override
  void initState() {
    super.initState();
    unawaited(OpenMojiCatalog.load().then((categories) {
      if (mounted) setState(() => _categories = categories);
    }),);
  }

  void _openDefaultToneStrip() => setState(() => _toneStripBase = '');

  void _openOverrideToneStrip(String base) =>
      setState(() => _toneStripBase = base);

  void _closeToneStrip() => setState(() => _toneStripBase = null);

  void _onToneSelected(SkinTone tone) {
    final base = _toneStripBase;
    _closeToneStrip();
    if (base == null) return;
    if (base.isEmpty) {
      widget.onSkinToneChanged?.call(tone);
    } else {
      widget.onSelected(applySkinTone(base, tone));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categories = _categories;
    if (categories == null) {
      return const Center(child: KoheraLoader());
    }

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search emoji',
                        prefixIcon: const Icon(KIcons.search, size: 20),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  if (widget.onSkinToneChanged != null) ...[
                    const SizedBox(width: 4),
                    Semantics(
                      button: true,
                      label: 'Default skin tone',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                        onTap: _openDefaultToneStrip,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: OpenMojiImage(
                              grapheme: widget.skinTone.sample,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _query.isEmpty
                  ? _CategoryTabs(
                      categories: categories,
                      icons: _icons,
                      columns: widget.columns,
                      skinTone: widget.skinTone,
                      onSelected: widget.onSelected,
                      onToneRequested: _openOverrideToneStrip,
                    )
                  : _EmojiGrid(
                      emoji: OpenMojiCatalog.search(_query),
                      columns: widget.columns,
                      skinTone: widget.skinTone,
                      onSelected: widget.onSelected,
                      onToneRequested: _openOverrideToneStrip,
                    ),
            ),
          ],
        ),
        if (_toneStripBase != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeToneStrip,
              child: Stack(
                children: [
                  // The default-tone strip drops from the header swatch
                  // (top-right); a per-emoji override sits near the bottom.
                  if (_toneStripBase!.isEmpty)
                    Positioned(
                      top: 52,
                      right: 8,
                      child: _ToneStrip(
                        base: _toneStripBase!,
                        selected: widget.skinTone,
                        onSelected: _onToneSelected,
                      ),
                    )
                  else
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: Center(
                        child: _ToneStrip(
                          base: _toneStripBase!,
                          onSelected: _onToneSelected,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Inline row of skin-tone swatches. For the default strip ([base] empty) the
/// swatches are sample hands; for an override they are the toned variants of
/// [base].
class _ToneStrip extends StatelessWidget {
  const _ToneStrip({
    required this.base,
    required this.onSelected,
    this.selected,
  });

  final String base;
  final ValueChanged<SkinTone> onSelected;

  /// Currently active tone, highlighted in the strip (default-tone mode).
  final SkinTone? selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tone in SkinTone.values)
              InkWell(
                borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                onTap: () => onSelected(tone),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                    color: tone == selected
                        ? cs.primary.withValues(alpha: 0.18)
                        : null,
                    border: tone == selected
                        ? Border.all(color: cs.primary, width: 1.5)
                        : null,
                  ),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: OpenMojiImage(
                      grapheme: base.isEmpty
                          ? tone.sample
                          : applySkinTone(base, tone),
                      size: 30,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.icons,
    required this.columns,
    required this.skinTone,
    required this.onSelected,
    required this.onToneRequested,
  });

  final List<OpenMojiCategory> categories;
  final Map<String, IconData> icons;
  final int columns;
  final SkinTone skinTone;
  final void Function(String emoji) onSelected;
  final void Function(String base) onToneRequested;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: categories.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            indicatorColor: cs.primary,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            tabs: [
              for (final c in categories)
                Tab(icon: Icon(icons[c.key] ?? KIcons.tag, size: 20)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in categories)
                  _EmojiGrid(
                    emoji: c.emoji,
                    columns: columns,
                    skinTone: skinTone,
                    onSelected: onSelected,
                    onToneRequested: onToneRequested,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
    required this.emoji,
    required this.columns,
    required this.skinTone,
    required this.onSelected,
    required this.onToneRequested,
  });

  final List<OpenMojiEmoji> emoji;
  final int columns;
  final SkinTone skinTone;
  final void Function(String emoji) onSelected;
  final void Function(String base) onToneRequested;

  @override
  Widget build(BuildContext context) {
    if (emoji.isEmpty) {
      return Center(
        child: Text(
          'No emoji found',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
      ),
      itemCount: emoji.length,
      itemBuilder: (context, i) {
        final e = emoji[i];
        final supportsTone = openMojiSupportsSkinTone(e.emoji);
        final shown = supportsTone ? applySkinTone(e.emoji, skinTone) : e.emoji;
        return InkWell(
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
          onTap: () => onSelected(shown),
          onLongPress:
              supportsTone ? () => onToneRequested(e.emoji) : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: OpenMojiImage(grapheme: shown),
          ),
        );
      },
    );
  }
}
